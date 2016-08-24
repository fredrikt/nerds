import argparse
import ConfigParser

class DefaultConf(object):
    def __init__(self, config):
        self.config = config

    def get(self, section, key, default=''):
        if self.config.has_option(section, key):
            return self.config.get(section, key)
        else:
            return default

    def has_option(self, section, option):
        return self.config.has_option(section, option)

    def get_section(self, section):
        return dict(self.config.items(section))

    def sections(self):
        return self.config.sections()

def cli():
    parser = argparse.ArgumentParser(description='SSH command producer.')
    parser.add_argument('--config', '-C', required=True, help='a configuration file')
    parser.add_argument('--out', '-O', default='.', help='an output directory')
    return parser.parse_args()

def load_config(filepath):
    conf = ConfigParser.SafeConfigParser()
    conf.read(filepath)
    return DefaultConf(conf)

