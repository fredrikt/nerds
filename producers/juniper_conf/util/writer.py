import json
import os

class JsonWriter:
    def __init__(self, dry_run=False, out_dir="json"):
        self.dry_run = dry_run
        self.out_dir = out_dir
        if not os.path.exists(out_dir):
            os.makedirs(out_dir)

    def write(self, router):
        template =  {'host':
                        {
                        'name': router.name,
                         'version': 1,
                         'juniper_conf': router.to_json()
                        }
                    }
        out = json.dumps(template, indent=4)
        if self.dry_run:
             print out
        else:
            self.write_to_file(out, router.name)

    def write_to_file(self,out, name):
        path = os.path.join(self.out_dir, name+".json")
        try:
            with open(path, 'w') as f:
                f.write(out)
        except IOError as (errno, strerror):
            #TODO: logging
            print "I/O error({0}): {1}".format(errno,strerror)


