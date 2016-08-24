import json
import os

def template(path, producer_name):
    if path:
        with open(path) as fp:
            _template = json.load(fp) 
    else:
        _template = {producer_name: True}

    return _template


def merge_nerds_file(file_name, new_nerds):
    with open(file_name, "r") as f:
        current = json.load(f)

    current.get('host').update(new_nerds.get('host'))
    return current

def save_to_json(nerds, out_dir):
    host = nerds.get('host', {}).get('name')
    if host and nerds:
        file_name = os.path.join(out_dir,"{}.json".format(host))
        if os.path.isfile(file_name):
                # Need to merge
                nerds = merge_nerds_file(file_name, nerds)
        with open(file_name, 'wb') as f:
            json.dump(nerds, f)
    else:
        pass
