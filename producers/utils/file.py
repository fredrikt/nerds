import json
import os


def merge_nerds_file(file_name, new_nerds):
    with open(file_name, "r") as f:
        try:
            current = json.load(f)
        except ValueError:
            current = None
        #except json.decoder.JSONDecodeError:
        #    current = None
    if current:
        current.get('host').update(new_nerds.get('host'))
    else:
        current = new_nerds
    return current


def save_to_json(nerds, out_dir):
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

    host = nerds.get('host', {}).get('name')
    if host and nerds:
        file_name = os.path.join(out_dir, "{}.json".format(host))
        if os.path.isfile(file_name):
            # Need to merge
            nerds = merge_nerds_file(file_name, nerds)
        with open(file_name, 'w') as f:
            json.dump(nerds, f, indent=4)
    else:
        pass
