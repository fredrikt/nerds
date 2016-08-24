import argparse
import ConfigParser

def cli():
    parser = argparse.ArgumentParser(description='SSH command producer.')
    parser.add_argument('--config', '-C', required=True, help='a configuration file')
    parser.add_argument('--out', '-O', help='an output directory')
    return parser.parse_args()

def load_config(filepath):
    conf = ConfigParser.SafeConfigParser()
    conf.read(filepath)
    return conf

