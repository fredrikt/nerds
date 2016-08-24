import csv as _csv
from .list_converter import to_nerds

def csv(producer_name, headers, lines, host_name='host_name'):
    result = []
    for producer_value in _csv.DictReader(lines,headers):
        host = producer_value.get(host_name)
        if host:
            del producer_value[host_name]

            result.append(to_nerds(host, producer_name, producer_value))
    return result

