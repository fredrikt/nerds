
def to_nerds(name, producer_name, data={}):
    nerds = {
        u'host': {
            u'version': 1,
            u'name': name,
        }
    }

    if producer_name:
        nerds[u'host'][producer_name] = data
    return nerds
