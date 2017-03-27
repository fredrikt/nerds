FROM python:2.7-alpine
MAINTAINER Markus Krogh <markus@nordu.net>
RUN mkdir /app
WORKDIR /app
RUN apk --no-cache add nmap && pip install python-nmap
ADD *.py /app
ENTRYPOINT ["python2", "nmap_services_py.py"]
CMD ["-h"]
