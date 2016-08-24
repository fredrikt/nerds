from fabric.api import run, settings, env, quiet, hosts
from cli import cli, load_config
from file import template, merge_nerds_file, save_to_json
import converters


# Would be nice to use hosts list instead of host_string...
def ssh_cmd(host, cmd, options={}):
    with settings(quiet(), use_ssh_config = True, host_string = host):
        output = run(cmd)
    return output


def handle_convert(host, lines, config, producer):
    converter = config.get('convert')
    producer_name = config.get('producer_name', producer)

    if converter in ('line_to_host'):
        _template = template(config.get('template'), producer_name)
        result = converters.list_to_hosts(lines, producer_name, _template)
    elif converter in ('to_list'):
        list_key = config.get('list_key', producer_name)
        result = [converters.to_list(host, lines, producer_name, list_key)]
    elif converter in ('split'):
        seperator = config.get('seperator', ',')
        result = [converters.split(host, producer_name, lines, seperator)]
    elif converter in ('csv_lines', 'csv'):
        host_key = config.get('host_key', 'host_name')
        header = config.get('header').split()
        result = converters.csv(producer_name, header, lines, host_key)
    else:
        result = []

    return result

def main(producers, config, args):
    base_hosts = config.get('base_conf', 'hosts')
    for producer in producers:
        hosts = config.get(producer, 'hosts', base_hosts).split()
        for host in hosts:
            producer_conf = config.get_section(producer)
            cmd = config.get(producer, 'cmd')

            lines = ssh_cmd(host, cmd).splitlines()
            result = handle_convert(host, lines, producer_conf, producer)
            # output result
            for nerds in result:
                save_to_json(nerds, args.out)


if __name__ == '__main__':
    args = cli()
    config = load_config(args.config)
    producers = config.sections()
    if 'base_conf' in producers:
        producers.remove('base_conf')
    
    main(producers, config, args)
        
