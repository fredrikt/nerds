def to_nerds(host, producer_name, value):
    return {
        "host": {
            "name": host,
            "version": 1,
            producer_name: value
        }
    }

def list_to_hosts(hosts, producer_name, template):
    # template load...
    return [to_nerds(host, producer_name, template) for host in hosts]

def to_list(host, _list, producer_name, list_key):
    return to_nerds(host, producer_name, {list_key: _list})

def split(host, producer_name, _list, seperator):
    split_list = [ line.split(seperator) for line in _list]
    result = { k.strip(): v.strip() for (k,v) in  split_list}
    return to_nerds(host, producer_name, result)
