from .base import ElementParser
from models.chassis import Chassis, ChassisModule

class ChassisParser:
    """
        Parses an xml node tree into a Chassis object.
    """
    def parse(self, nodeTree):
        """
            Parses the first chassis node in supplied xml node tree.
        """
        chassisNode = ElementParser(nodeTree).first("chassis")
        return self._create_chassis(chassisNode)
    def parseAll(self, nodeTree):
        return [self._create_chassis(n) for n in ElementParser(nodeTree).all("chassis")]

    def _create_chassis(self, node):
        """
            Creates a chassis form a chassis node.
        """
        chassis = Chassis()
        chassis.name = node.first("name").text()
        chassis.serial_number = node.first("serial-number").text()
        chassis.description = node.first("description").text()
        chassis.modules = [self._create_module(m) for m in node.all("chassis-module")]
        return chassis

    def _create_module(self, node):
        """
            Creates a chassis module from a module node.
            Will also parse sub modules.
        """
        module = ChassisModule()
        module.name = node.first("name").text()
        module.version = node.first("version").text()
        module.part_number = node.first("part-number").text()
        module.serial_number = node.first("serial-number").text()
        module.description = node.first("description").text()
        module.model_number = node.first("model-number").text()
        module.clei_code = node.first("clei-code").text()
        module.clei_code = node.first("clei-code").text()
        module.sub_modules = [ self._create_module(ElementParser(c))
                for c in node.nodeTree.childNodes if "-module" in c.nodeName ]
        return module
