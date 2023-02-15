# conf needs to be an itterator, not an array for this to work
def parse(conf):
    data = {}
    for line in conf:
        tline = line.strip()
        if tline.startswith("#"):
            # ignore comments
            continue
        if tline.endswith('}'):
            return data
        if tline.endswith(';'):
            # got a value
            parts = tline[:-1].split(" ", 1)
            if len(parts) == 1:
                data[parts[0]] = True
                continue
            key, val = parts
            # check if value has quotes...
            if val.startswith('['):
                # got an array
                val = val[1:-1].split()
            elif val.startswith('"'):
                val = val[1:-1]
            data[key] = val
        if tline.endswith("{"):
            parts = tline.split()
            key = ' '.join(parts[:-1])
            data[key] = parse(conf)
    return data


def get_hostname(data):
    hostname = data['system'].get('host-name')
    domain = data['system'].get('domain-name')
    if not hostname:
        # try out groups.re0.system.host-name
        hostname = data.get('groups', {}).get('re0', {}).get('system', {}).get('host-name')
        if not hostname:
            return None
    if 're0' in hostname:
        hostname = hostname.replace('-re0', '')
    if domain:
        hostname = f'{hostname}.{domain}'
    return hostname


def is_juniper(conf):
    # first 5 lines should include version
    i = 0
    for line in conf:
        if i > 5:
            conf.seek(0)
            return False
        if line.startswith('version'):
            conf.seek(0)
            return True
        i += 1


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('conf')
    args = parser.parse_args()

    with open(args.conf) as f:
        import json
        data = parse(f)
        name = get_hostname(data)
        print(name)
        print(json.dumps(data, indent=4))
