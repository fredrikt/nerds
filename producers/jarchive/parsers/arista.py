# conf needs to be an itterator, not an array for this to work
def parse(conf, recursive=False):
    data = {}
    for line in conf:
        tline = line.strip()
        if recursive and tline == '!':
            return data
        if tline.startswith('!') or tline == 'end':
            # ignore comment
            continue
        # vlans and interfaces
        if tline.startswith('vlan') or tline.startswith('interface'):
            key, vlan = tline.split()
            key = f'{key}s'
            if key not in data:
                data[key] = {}
            data[key][vlan] = parse(conf, recursive=True)
        # other keys
        elif tline.startswith('hostname'):
            data['hostname'] = tline.split()[-1]
        elif tline.startswith('ip domain-name'):
            data['domain-name'] = tline.split()[-1]
        elif tline.startswith('ip address'):
            data['ip-address'] = tline.split()[-1]
        elif any([tline.startswith(p) for p in ['description', 'name', 'mlag']]):
            key, val = tline.split(' ', 1)
            if val.startswith('"'):
                val = val[1: -1]
            data[key] = val
    return data


def is_ariasta(conf):
    i = 0
    for line in conf:
        if i > 5:
            conf.seek(0)
            return False
        # will be in the first 5 lines normally
        if line.startswith('!'):
            # arista comment found
            conf.seek(0)
            return True
        i += 1


def get_hostname(data):
    hostname = data['hostname']
    domain = data['domain-name']
    if domain:
        hostname = f'{hostname}.{domain}'
    return hostname


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
