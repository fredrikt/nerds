#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Copyright 2010, NORDUnet A/S.
#
# This file is part of the NERDS producer juniper_conf.py.
#
# NORDUbot is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# NORDUbot is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with NERDS. If not, see <http://www.gnu.org/licenses/>.

from xml.dom import minidom
import sys
import json
import ConfigParser
import argparse

'''
Depends on pexpect for remote config gathering.
If you have Python <2.7 you need to install argparse manually.
'''

class Router:
	def __init__(self):
		self.name = ''
		self.interfaces = []

	def to_json(self):
		j = {'name':self.name}
		interfaces = []
		for interface in self.interfaces:
			interfaces.append(interface.to_json())
		j['interfaces'] = interfaces
		return j

class Interface:
	def __init__(self):
		self.name = ''
		self.bundle = ''
		self.desc = ''
		self.vlantagging = ''
		self.tunneldict = []
		# Unit dict is a list of dictionaries containing units to
		# interfaces, should be index like {'unit': 'name',
		# 'desc': 'foo', 'vlanid': 'bar', 'address': 'xyz'}
		self.unitdict = []

	def to_json(self):
		j = {'name':self.name, 'bundle':self.bundle, 'desc':self.desc,
			'vlantagging':self.vlantagging, 'tunnels':self.tunneldict,
			'units':self.unitdict}
		return j

def get_firstchild(element, arg):
	'''
	Helper function, takes xmlelement and a string.
	Returns a string.
	'''
	data = element.getElementsByTagName(arg).item(0).firstChild.data
	return data

def parse(xmldoc):
	'''
	Takes a JUNOS conf in XML format and returns a list of class
	Interface objects
	'''
	re = xmldoc.getElementsByTagName('host-name')
	hostname = ''
	interface = ''
	interfaces = xmldoc.getElementsByTagName('interfaces')
	router = Router()
	listofinterfaces = []

	try:
		hostname = re[0].firstChild.data
	except AttributeError:
		print 'No hostname in config file, check the conf and cry!!'
		sys.exit(1)

	if 're0' in hostname or 're1' in hostname:
		hostname = hostname.replace('-re0','').replace('-re1','')
	router.name = hostname

	for item in interfaces:
		try:
			interface = (xmldoc.getElementsByTagName('interface'))
		except AttributeError:
			pass

	for elements in interface:
		tempInterface = Interface()
		try:
			temp = get_firstchild(elements, 'name')
		except AttributeError:
			pass
		if '.' not in temp and 'lo' not in temp and 'all' not in temp and '*' not in temp:
			try:
				tempInterface.name = get_firstchild(elements, 'name')
			except AttributeError:
				pass
			try:
				vlantag = elements.getElementsByTagName('vlan-tagging').item(0)
				if vlantag != None:
					tempInterface.vlantagging = True
				else:
					tempInterface.vlantagging = False
			except AttributeError:
				pass
			try:
				tempInterface.bundle = get_firstchild(elements, 'bundle')
			except AttributeError:
				pass
			try:
				tempInterface.desc = get_firstchild(elements, 'description')
			except AttributeError:
				tempInterface.desc = 'No description set, fix me!'
			try:
				tempInterface.tunneldict.append({'source' :get_firstchild(elements, 'source'), 'destination': get_firstchild(elements, 'destination') })
			except AttributeError:
				pass
			# If is a interface is a AE interface, it should never have
			# units. If it has it is inactive conf in the router
			# if tempInterface.bundle == '':
			units = elements.getElementsByTagName('unit')
			unitemp = ''
			desctemp = ''
			vlanidtemp = ''
			nametemp = ''
			for unit in units:
				unittemp = get_firstchild(unit, 'name')
				try:
					desctemp = get_firstchild(unit, 'description')
				except AttributeError:
					pass
				try:
					vlanidtemp = get_firstchild(unit, 'vlan-id')
				except AttributeError:
					pass
				addresses = unit.getElementsByTagName('address')
				nametemp = []
				for address in addresses:
					nametemp.append(get_firstchild(address, 'name'))

				tempInterface.unitdict.append({'unit': unittemp, 'name': desctemp, 'vlanid': vlanidtemp, 'address': nametemp})
			listofinterfaces.append(tempInterface)
	router.interfaces = listofinterfaces
	return router

def init_config(path):
	'''
	Initializes the configuration file located in the path provided.
	'''
	try:
	   config = ConfigParser.SafeConfigParser()
	   config.read(path)
	   return config
	except IOError as (errno, strerror):
		print "I/O error({0}): {1}".format(errno, strerror)

def get_remote_conf(host, username, password):
	'''
	Tries to ssh to the supplied JunOS machine and execute the command
	to show current configuration i XML format.

	Returns False if the configuration could not be retrived.
	'''
	import pexpect

	try:
		s = pexpect.spawn('ssh %s@%s' % (username,host))
		s.expect('password')
		s.sendline(password)
		s.expect('>')
		# Send JunOS command for displaying the configuration in XML
		# format.
		s.sendline ('show configuration | display xml | no-more')
		s.expect('</rpc-reply>') # expect end of the XML blob
		xml = s.before # print everything before last expect()
		s.sendline('exit')
	except pexpect.ExceptionPexpect:
		print 'Could not log in to %s.' % host
		return False

	xml += '</rpc-reply>' # Add the end element as pexpect steals it
	# Remove the first line in the output which is the command sent
	# to JunOS.
	xml = xml.lstrip('show configuration | display xml | no-more')
	try:
		xmldoc = minidom.parseString(xml)
	except ExpatError:
		print 'Malformed XML input from %s.' % host
		return False

	return xmldoc

def main():

	# User friendly usage output
	parser = argparse.ArgumentParser()
	parser.add_argument('-C', nargs='1', help='Path to the \
configuration file.')
	parser.add_argument('-O', nargs='?', help='Path to output directory.')
	parser.add_argument('-N', action='store_true',
		help='Don\'t write output to disk.')
	args = parser.parse_args()

	# Load the configuration file
	config = init_config(args.C)

	# List to collect configuration in XML format for parsing
	xmldocs = []

	# Local files
	local_list = config.get('sources', 'local').split()
	for host in remote_list:
		pass # TODO

	# Remote hosts
	remote_list = config.get('sources', 'remote').split()
	for host in remote_list:
		xmldoc = get_remote_conf(host)
		if xmldoc:
			xmldocs.append(xmldoc)

	routerlist = []
	for doc in xmldocs:
		routerlist.append(parse(xmldoc))

	for router in routerlist:
		template = {'host':{'name': router.name, 'version': 1,
			'juniper_conf': {}}}
		template['host']['juniper_conf'] = router.to_json()
		out[router.name] = json.dumps(template, indent=4}

	# Output directory should be ./json/ if nothing else is specified
	out_dir = './json/'

	if args.N is True:
		for key in out:
			print out[key]
	else:
		if args.O:
			out_dir = args.O
		# Pad with / if user provides a broken path
		if out_dir[-1] != '/':
			out_dir += '/'
		for key in out:
			try:
				try:
					f = open('%s%s' % (out_dir, key), 'w')
				except IOError:
					# The directory to write in must exist
					os.mkdir(out_dir)
					f = open('%s%s' % (out_dir, key), 'w')
				f.write(out[key])
				f.close()
			except IOError as (errno, strerror):
				print "I/O error({0}): {1}".format(errno, strerror)

	return 0

if __name__ == '__main__':
	main()

