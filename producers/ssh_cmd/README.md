
"Meta" producer that can ssh to one or more machines and run commands that are transformed into nerds data.

## Config

    [base_conf]
    user =
    password =
    hosts = one.example.org two.example.org
    merge = true


    [syslog]
    cmd = find /var/log/rsyslog/ -maxdepth 1 -mmin -1440 -type d -exec basename "{}" \;
    convert = line_to_host
    template = syslog.json

    [rsyslog]
    cmd = find /var/log/rsyslog/ -maxdepth 1 -mmin -1440 -type d -exec basename "{}" \;
    convert = to_list
    list_key = "hosts"

    [mem_info]
    name = memory_info
    cmd = cat /proc/meminfo | head -n2
    convert = split
    seperator = :
    
    [csv]
    cmd = something_that_outputs_csv_lines
    convert = csv_lines
    header = name ip other_attribute

    [json]
    cmd = something_that_outputs_json
    convert = json

### Template examples

    //syslog.json
    {
      "syslog": true
    }

### Example of outputs

    //syslog, 1 file pr line:
    {
      "host": {
        "name": "what_was_in_the_line",
        "version": 1,
        "syslog": {
          "syslog": true
        }
      }
    }


    //rsyslog
    {
      "host": {
        "name": "syslog.example.com",
        "version": 1,
        "rsyslog": {
          "hosts": [
            "machine1.example.com",
            "machine2.example.com",
            "somewhere",
            "::1"
          ]
        }
      }
    }

    //mem_info
    {
      "host": {
        "name": "one.example.org",
        "version": 1,
        "memory_info": {
          "MemTotal": "3969876 kB",
          "MemFree": "120056 kB"
        }
    }

