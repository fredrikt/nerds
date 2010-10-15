#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
#       juniper_conf.py
#       
#       Copyright 2010 Erik Nihlén <erik@nordu.net>
#       
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#       
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#       
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.

from xml.dom import minidom
import sys
import json
import argparse

'''
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
		'''Unit dict is a list of dictionaries containing units to
		interfaces, should be index like {'unit': 'name', 'desc': 'foo',
		'vlanid': 'bar', 'address': 'xyz'}
		'''
		self.unitdict = []
	def to_json(self):
		j = {'name':self.name, 'bundle':self.bundle, 'desc':self.desc,
			'vlantagging':self.vlantagging, 'tunnels':self.tunneldict,
			'units':self.unitdict}
		return j
		
def get_firstchild(element, arg):
	""" Helper function, takes xmlelement and a string. Returns a string
	"""
	data = element.getElementsByTagName(arg).item(0).firstChild.data
	return data

def parse(xmldoc):
	"""Takes a JUNOS conf in XML format and returns a list of
	Class interface objects"""
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
			#if tempInterface.bundle == '':	
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

def get_remote_conf(host):
	import pexpect
	
			

def main():
	# User friendly usage output
	parser = argparse.ArgumentParser()
	parser.add_argument('-O', nargs='?', help='Path to output directory.')
	parser.add_argument('-N', action='store_true',
		help='Don\'t write output to disk.')
	parser.add_argument('-L', nargs='?', help='Path to local file with\
list of the config files.')
	parser.add_argument('-R', nargs='?', help='Path to local file with\
list of host names.')
	args = parser.parse_args()
	
	if args.L != '':
		pass
	if args.R != '':
		try:
			f = open(args.R)
			xmldoc = []
			for host in f:
				xmldocs.append(get_remote_conf(host))
				
		except IOError as (errno, strerror):
			print "I/O error({0}): {1}".format(errno, strerror)
		
	
	# Output directory should be ./json/ if nothing else is specified
	out_dir = './json/'

	if args.N is True:
		print out
	else:
		if args.O:
			out_dir = args.O
		if out_dir[-1] != '/': # Pad with / if user provides a broken path
			out_dir += '/'
		try:
			try:
				f = open('%s%s' % (out_dir, hostn), 'w')
			except IOError:
				os.mkdir(out_dir) # The directory to write in must exist
				f = open('%s%s' % (out_dir, hostn), 'w')
			f.write(out)
			f.close()
		except IOError as (errno, strerror):
			print "I/O error({0}): {1}".format(errno, strerror)
	
	#conflist = ['se-tug-xml', 'se-fre-xml', 'se-tug2-xml']
	routerlist = []
	for item in conflist:
		xmldoc = minidom.parse(item)
		routerlist.append(parse(xmldoc))
	for item in routerlist:
		template = {'host':{'name': item.name, 'version': 1, 'juniper_conf': {}}}
		template['host']['juniper_conf'] = item.to_json()
		out = json.dumps(template, sort_keys=False, indent=4)
		print out

			
			
		
	return 0
	

if __name__ == '__main__':
	main()

