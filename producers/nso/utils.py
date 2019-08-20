def find(what, data, delimiter='.', default=None):
    paths = what.split(delimiter)
    elm = data
    for p in paths:
        if p not in elm:
            elm = default
            break
        elm = elm[p]
    return elm


def find_first(what, data, default=None):
    result = find_all(what, data)
    if result:
        return result[0]
    else:
        return default


def find_all(what, data, result=None):
    if result is None:
        result = []
    if isinstance(data, list):
        for v in data:
            find_all(what, v, result)
    if isinstance(data, dict):
        for k, v in data.items():
            if k == what:
                result.append(v)
            else:
                find_all(what, v, result)
    return result


def hostname_clean(host):
    return host.replace('lo0.', '')
