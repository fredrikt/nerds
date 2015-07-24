from models import Interface
from .base import ElementParser

class InterfaceParser:
    def parse(self, nodeTree, physicalInterfaces=[]):
        interfaceNodes = [ 
                interface for i in ElementParser(nodeTree).all("interfaces") 
                if i.parent().tag() in ['configuration']
                for interface in i.all("interface") ]

        interfaces = []
        for node in interfaceNodes:
            interface = Interface()
            interface.name = node.first("name").text()
            if physicalInterfaces:
                if not interface.name in physicalInterfaces:
                    #TODO: warning about configured IF that does not exist
                    #logger.warn('Interface %s is configured but not found in %s.' % (tempInterface.name, get_hostname(xmldoc)))
                    print "Interface {0} is configured but not found".format(interface.name)
                    continue
                else:
                    physicalInterfaces.remove(interface.name)

            interface.vlantagging = len(node.all("vlan-tagging")) > 0
            interface.bundle = node.first("bundle").text()
            interface.description = node.first("description").text()
            #TODO: tunnel dict..?
            interface.tunneldict.append({
                'source': node.first("source").text(),
                'destination': node.first("destination").text(),
                })

            #Units
            interface.unitdict = [ self._unit(u) for u in node.all("unit") ]
            interfaces.append(interface)
        for iface in physicalInterfaces:
            interface = Interface()
            interface.name = iface
            interfaces.append(interface)

        return interfaces

    def _unit(self, unit):
        return {
                'unit': unit.first("name").text(),
                'description': unit.first("description").text(),
                'vlanid': unit.first("vlan-id").text(),
                'address': [ a.first("name").text() for a in unit.all("address") ],
                }
