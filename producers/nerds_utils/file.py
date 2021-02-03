import json
import os


def merge_nerds_file(current, new_nerds):
    if current:
        current.get('host').update(new_nerds.get('host'))
    else:
        current = new_nerds
    return current


def load_nerds_file(file_name):
    with open(file_name, "r") as f:
        try:
            current = json.load(f)
        except ValueError:
            current = None
    return current


def save_to_json(nerds, out_dir, merge=merge_nerds_file, sort_keys=True):
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

    if nerds:
        host = nerds.get('host', {}).get('name')
        if host and nerds:
            file_name = os.path.join(out_dir, "{}.json".format(host.lower()))
            if os.path.isfile(file_name):
                # Need to merge
                current = load_nerds_file(file_name)
                nerds = merge(current, nerds)
            with open(file_name, 'w') as f:
                json.dump(nerds, f, indent=4, sort_keys=sort_keys)
        else:
            pass
