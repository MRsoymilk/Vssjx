"""Export every monster ANI for the read-only browser, not gameplay rules."""
if __package__:
    from .import_animation_catalog import export_catalog as export_animations
else:
    from import_animation_catalog import export_catalog as export_animations


def export_catalog(destination=None):
    return export_animations('monster', destination)


if __name__ == '__main__':
    catalog = export_catalog()
    print(f"Exported {catalog['animation_count']} monster animations / {catalog['image_member_count']} image members")
