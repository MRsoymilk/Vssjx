import copy
import json
import os
from pathlib import Path
import tempfile
import unittest

from run_capacity import proc_sample
from summarize_capacity import database_resources, resources, summarize


class CapacityToolsTest(unittest.TestCase):
    def fixture(self, directory, moving=60):
        result = {'stage': {'name': 'fixture', 'players': 10, 'moving_percent': moving, 'seconds': 10},
                  'measured_seconds': 10, 'active_at_start': 10, 'active_at_end': 10,
                  'clients_ever_saw_entire_population': 10, 'errors': {},
                  'moves_sent': 30 if moving else 0, 'full_population_snapshots': 1000 if moving else 0,
                  'ping_roundtrip': {'p95_ms': 10}, 'movement_snapshot_observation': {'p95_ms': 100 if moving else None},
                  'chat_sends': 10, 'chat_accepted': 10, 'chat_deliveries': 100, 'chat_delivery': {'p95_ms': 100}}
        (directory / 'environment.json').write_text('{}')
        (directory / 'samples.json').write_text('[]')
        self.store(directory, result)
        return result

    def store(self, directory, result):
        (directory / 'results.json').write_text(json.dumps({'setup': {}, 'results': [result]}))

    def test_current_process_resource_reader(self):
        sample = proc_sample(os.getpid())
        self.assertGreater(sample['rss_mib'], 0)
        self.assertGreater(sample['threads'], 0)
        self.assertGreater(sample['fds'], 0)

    def test_cpu_percent_counts_each_core(self):
        samples = [{'time_unix': second, 'server': {'cpu_seconds': second * 4, 'rss_mib': 10, 'fds': 20, 'threads': 8}} for second in [1, 2, 3]]
        self.assertEqual(resources(samples, 'server')['cpu_mean_percent_one_core_100'], 400)

    def test_database_resource_units(self):
        values = database_resources([{'database_container': {'CPUPerc': '125.50%', 'MemUsage': '0.5GiB / 15GiB'}}])
        self.assertEqual(values['memory_peak_mib'], 512)
        self.assertEqual(values['cpu_mean_percent_one_core_100'], 125.5)

    def test_healthy_short_movement_fixture(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as scratch:
            directory = Path(scratch)
            self.fixture(directory)
            result = summarize(directory)['results'][0]
            self.assertEqual(result['expected_fixed_rate_moves'], 30)
            self.assertEqual(result['preliminary_gate'], 'PASS')

    def test_idle_connections_never_substitute_for_movement(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as scratch:
            directory = Path(scratch)
            idle = self.fixture(directory, moving=0)
            self.assertEqual(summarize(directory)['results'][0]['preliminary_gate'], 'PASS')
            idle['stage']['moving_percent'] = 60
            self.store(directory, idle)
            self.assertEqual(summarize(directory)['results'][0]['preliminary_gate'], 'FAIL')

    def test_missing_players_errors_and_slow_generator_are_not_success(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as scratch:
            directory = Path(scratch)
            good = self.fixture(directory)
            for field, value in [('active_at_end', 9), ('clients_ever_saw_entire_population', 9), ('moves_sent', 10), ('errors', {'DATABASE_UNAVAILABLE': 1}), ('full_population_snapshots', 50), ('chat_deliveries', 20)]:
                changed = copy.deepcopy(good)
                changed[field] = value
                self.store(directory, changed)
                self.assertEqual(summarize(directory)['results'][0]['preliminary_gate'], 'FAIL', field)

    def test_delta_frontiers_require_complete_populations_and_each_client_stays_fresh(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as scratch:
            directory = Path(scratch)
            result = self.fixture(directory)
            result.update(world_sync_version=2, full_visibility_at_start=10, full_population_state_updates=1000, minimum_client_state_updates=100)
            # Actual protocol does not repeat full snapshots after initial install.
            result['full_population_snapshots'] = 0
            self.store(directory, result)
            self.assertEqual(summarize(directory)['results'][0]['preliminary_gate'], 'PASS')
            for field,value in [('minimum_client_state_updates', 20), ('full_visibility_at_start', 9)]:
                bad = copy.deepcopy(result)
                bad[field] = value
                self.store(directory, bad)
                self.assertEqual(summarize(directory)['results'][0]['preliminary_gate'], 'FAIL', field)


if __name__ == '__main__': unittest.main()
