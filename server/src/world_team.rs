//! Server-owned party motion. Followers walk ordinary routes at ordinary speed.
use super::*;
use std::collections::{BTreeMap, VecDeque};

#[derive(Clone, PartialEq, Eq)]
pub(crate) struct Member {
    pub id: Uuid,
    pub team: Uuid,
    pub leader: Uuid,
    pub following: bool,
    pub ready: bool,
    pub order: usize,
}

#[derive(Clone)]
struct Exit {
    from: String,
    to: String,
    cell: [i32; 2],
    action: String,
    target: String,
    created: Instant,
}
#[derive(Default)]
pub(super) struct Following {
    revision: u64,
    members: HashMap<Uuid, Member>,
    exits: HashMap<Uuid, VecDeque<Exit>>,
}
pub(crate) async fn roster(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    team: Uuid,
) -> Result<Vec<Member>, AuthError> {
    let rows = sqlx::query("SELECT m.character_id,m.following,m.ready,l.character_id AS leader FROM team_members m JOIN team_members l ON l.team_id=m.team_id AND l.leader WHERE m.team_id=$1 ORDER BY m.leader DESC,m.joined_at,m.character_id")
        .bind(team).fetch_all(&mut **tx).await.map_err(db_error)?;
    Ok(rows
        .iter()
        .enumerate()
        .map(|(order, r)| Member {
            id: r.get("character_id"),
            team,
            leader: r.get("leader"),
            following: r.get("following"),
            ready: r.get("ready"),
            order,
        })
        .collect())
}
impl WorldHub {
    pub(crate) fn team_roster_sync(&self, affected: &[Uuid], members: Vec<Member>) {
        let mut s = self.data.lock().expect("world state");
        let affected: std::collections::HashSet<_> = affected.iter().copied().collect();
        for id in &affected {
            let next = members.iter().find(|m| m.id == *id);
            if s.following.members.get(id) != next {
                s.following.revision += 1;
                let mut previous = s.following.members.get(id).cloned();
                if let (Some(old), Some(new)) = (&mut previous, next) {
                    old.ready = new.ready;
                }
                // Readiness is display state, not a change to the follow route.
                if previous.as_ref() != next {
                    s.following.exits.remove(id);
                    if let Some(a) = s.actors.get_mut(id) {
                        a.motion.stop();
                    }
                }
            }
            s.following.members.remove(id);
        }
        for m in members {
            s.following.members.insert(m.id, m);
        }
    }
    pub(super) async fn restore_team_roster(
        &self,
        auth: &AuthService,
        id: Uuid,
    ) -> Result<(), AuthError> {
        let _update = self.team_updates.lock().await;
        let mut tx = auth.pool().begin().await.map_err(db_error)?;
        // Same lock as team mutations: a delayed join must not resurrect removed membership.
        sqlx::query("SELECT pg_advisory_xact_lock(773913019)")
            .execute(&mut *tx)
            .await
            .map_err(db_error)?;
        let team: Option<Uuid> =
            sqlx::query_scalar("SELECT team_id FROM team_members WHERE character_id=$1")
                .bind(id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(db_error)?;
        let members = if let Some(t) = team {
            roster(&mut tx, t).await?
        } else {
            vec![]
        };
        let mut affected: Vec<_> = members.iter().map(|m| m.id).collect();
        affected.push(id);
        self.team_roster_sync(&affected, members);
        tx.commit().await.map_err(db_error)?;
        Ok(())
    }
    pub(super) fn following(s: &StateData, id: Uuid) -> bool {
        s.following
            .members
            .get(&id)
            .is_some_and(|m| m.id != m.leader && m.following)
    }
    pub(super) fn follow_tick(&self, s: &mut StateData) {
        let mut members: Vec<_> = s.following.members.values().cloned().collect();
        members.sort_by_key(|m| (m.team, m.order));
        let mut previous: HashMap<Uuid, Uuid> = HashMap::new();
        for m in members {
            if m.id == m.leader {
                previous.insert(m.team, m.id);
                continue;
            }
            if !m.following {
                continue;
            }
            let ahead = previous.get(&m.team).copied().unwrap_or(m.leader);
            let available = |id| {
                s.actors.get(&id).filter(|a| {
                    a.connected && !a.in_battle && !s.team_busy.contains(&id) && !s.duels.active(id)
                })
            };
            let Some(leader) = available(m.leader) else {
                if let Some(a) = s.actors.get_mut(&m.id) {
                    a.motion.stop();
                }
                continue;
            };
            let Some(actor) = available(m.id) else {
                continue;
            };
            let map_id = actor.map_id.clone();
            let start = actor.motion.next.unwrap_or(actor.motion.cell);
            let mut goal = None;
            let exits = s.following.exits.entry(m.id).or_default();
            let before = exits.len();
            if leader.map_id == map_id {
                exits.clear();
            }
            while exits
                .front()
                .is_some_and(|e| e.to == map_id || e.created.elapsed() > Duration::from_secs(120))
            {
                exits.pop_front();
            }
            if exits.len() != before {
                s.following.revision += 1;
            }
            if let Some(exit) = exits.front().filter(|e| e.from == map_id) {
                goal = Some(exit.cell);
            } else if leader.map_id == map_id {
                let target = s
                    .actors
                    .get(&ahead)
                    .filter(|a| a.connected && a.map_id == map_id)
                    .unwrap_or(leader);
                // Follow the predecessor's last completed cell; leave one cell when stationary.
                let distance = (start[0] - target.motion.cell[0]).abs()
                    + (start[1] - target.motion.cell[1]).abs();
                if distance > 1 || target.motion.next.is_some() {
                    goal = Some(target.motion.cell);
                }
                previous.insert(m.team, m.id);
            }
            let a = s.actors.get_mut(&m.id).unwrap();
            if let Some(goal) = goal {
                if a.motion.route.back().copied().or(a.motion.next) != Some(goal) {
                    if !a.motion.move_to(self.map_for(&map_id), goal) {
                        a.motion.stop();
                    }
                }
            } else {
                a.motion.stop();
            }
        }
    }
    pub(super) fn follow_departed(
        &self,
        id: Uuid,
        from: &str,
        to: &str,
        cell: [i32; 2],
        command: &crate::pve_rules::Command,
    ) {
        if !matches!(
            command.action,
            crate::pve_rules::Action::Transfer | crate::pve_rules::Action::AiTravel
        ) {
            return;
        }
        let mut s = self.data.lock().expect("world state");
        let Some(m) = s
            .following
            .members
            .get(&id)
            .filter(|m| m.leader == id)
            .cloned()
        else {
            return;
        };
        let ids: Vec<_> = s
            .following
            .members
            .values()
            .filter(|v| v.team == m.team && v.id != id && v.following)
            .map(|v| v.id)
            .collect();
        for id in ids {
            s.following.revision += 1;
            if !s.actors.get(&id).is_some_and(|a| a.connected) {
                continue;
            }
            let queue = s.following.exits.entry(id).or_default();
            if queue.len() >= 16 {
                queue.clear();
                continue;
            }
            queue.push_back(Exit {
                from: from.into(),
                to: to.into(),
                cell,
                action: if command.action == crate::pve_rules::Action::Transfer {
                    "transfer"
                } else {
                    "ai_travel"
                }
                .into(),
                target: command.target.clone().unwrap_or_default(),
                created: Instant::now(),
            });
        }
    }
    pub(super) fn team_packet(
        &self,
        owner: &Ownership,
        after: Option<(u64, u64)>,
    ) -> Option<((u64, u64), Value)> {
        let s = self.data.lock().expect("world state");
        let stamp = (s.following.revision, s.appearance_revision);
        if after == Some(stamp) {
            return None;
        }
        let members: BTreeMap<_, _> = s
            .following
            .members
            .values()
            .filter(|m| {
                s.actors
                    .get(&m.id)
                    .is_some_and(|a| a.connected && a.map_id == owner.map_id)
            })
            .map(|m| {
                (
                    m.id.to_string(),
                    json!({"leader":m.id==m.leader,"following":m.following,"ready":m.ready}),
                )
            })
            .collect();
        let travel = s
            .following
            .exits
            .get(&owner.id)
            .and_then(|q| q.front())
            .filter(|e| e.from == owner.map_id && e.created.elapsed() < Duration::from_secs(120))
            .map(|e| json!({"action":e.action,"target":e.target,"cell":e.cell}));
        Some((
            stamp,
            json!({"type":"world.team","map_id":owner.map_id,"members":members,"following":Self::following(&s,owner.id),"travel":travel}),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn readiness_updates_markers_without_discarding_portal_navigation() {
        let hub = WorldHub::new(WorldConfig::default());
        let mut member = Member {
            id: Uuid::new_v4(), team: Uuid::new_v4(), leader: Uuid::new_v4(),
            following: true, ready: false, order: 1,
        };
        hub.team_roster_sync(&[member.id], vec![member.clone()]);
        let revision = {
            let mut state = hub.data.lock().unwrap();
            state.following.exits.insert(member.id, VecDeque::from([Exit {
                from: "qingyun_trail".into(), to: "ancient_ruins".into(),
                cell: [28, 16], action: "transfer".into(), target: "ruins_gate".into(),
                created: Instant::now(),
            }]));
            state.following.revision
        };
        member.ready = true;
        hub.team_roster_sync(&[member.id], vec![member.clone()]);
        {
            let state = hub.data.lock().unwrap();
            assert!(state.following.revision > revision);
            assert!(state.following.members[&member.id].ready);
            assert_eq!(state.following.exits[&member.id].len(), 1);
        }
        member.following = false;
        hub.team_roster_sync(&[member.id], vec![member.clone()]);
        assert!(!hub.data.lock().unwrap().following.exits.contains_key(&member.id));
    }
}
