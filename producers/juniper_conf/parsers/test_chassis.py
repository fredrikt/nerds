from .chassis import ChassisParser
import unittest
from xml.dom import minidom


class ChassisParserTest(unittest.TestCase):
    def setUp(self):
        xml = minidom.parse("parsers/chassis-test.xml")
        self.chassis = ChassisParser().parse(xml)

    def test_chasis_info(self):
        self.assertEqual(self.chassis.name, "Chassis")
        self.assertEqual(self.chassis.serial_number, "11111")
        self.assertEqual(self.chassis.description, "T4000")
        self.assertEqual(len(self.chassis.modules), 4)

    def test_first_module(self):
        module = self.chassis.modules[0]
        self.assertEqual(module.name, "Midplane")
        self.assertEqual(module.version, "REV 03")
        self.assertEqual(module.part_number, "111-111111")
        self.assertEqual(module.serial_number, "xxxxx1")
        self.assertEqual(module.description, "T640 Backplane")
        self.assertEqual(module.model_number, "CHAS-BP-T640-S")

    def test_sub_modules(self):
        module = [m for m in self.chassis.modules if m.name == "FPC 0"][0]

        self.assertEqual(module.name, "FPC 0")
        self.assertEqual(module.version, "REV 02")
        self.assertEqual(module.part_number, "444-444444")
        self.assertEqual(module.serial_number, "4")
        self.assertEqual(module.description, "FPC Type 5-3D")
        self.assertEqual(module.clei_code, "FPCSWEETOK")
        self.assertEqual(module.model_number, "T4000-FPC5-3D")
        self.assertEqual(len(module.sub_modules), 2)

    def test_subsub_modules(self):
        fpc = [m for m in self.chassis.modules if m.name == "FPC 0"][0]
        module = [m for m in fpc.sub_modules if m.name == "PIC 0"][0]

        self.assertEqual(module.name, "PIC 0")
        self.assertEqual(module.version, "REV 17")
        self.assertEqual(module.part_number, "666-666666")
        self.assertEqual(module.serial_number, "xxxxxxx6")
        self.assertEqual(module.description, "12x10GE (LAN/WAN) SFPP")
        self.assertEqual(module.clei_code, "TENGYEAHOK")
        self.assertEqual(module.model_number, "PF-12XGE-SFPP")
        self.assertEqual(len(module.sub_modules), 2)

        sub_module = module.sub_modules[0]
        self.assertEqual(sub_module.name, "Xcvr 0")
        self.assertEqual(sub_module.version, "REV 01")
        self.assertEqual(sub_module.part_number, "777-777777")
        self.assertEqual(sub_module.serial_number, "xxxxxx7")
        self.assertEqual(sub_module.description, "SFP+-10G-LR")
