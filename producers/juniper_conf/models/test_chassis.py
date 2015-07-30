from .chassis import Chassis, ChassisModule
import unittest

class ChassisTest(unittest.TestCase):

    def setUp(self):
        chassis = Chassis()
        chassis.name = "Test"
        chassis.serial_number = "1234"
        chassis.description = "Awesome chassis"

        module = ChassisModule()
        module.name="module"
        module.part_number="part1"
        chassis.modules = [module]
        self.chassis = chassis

    def test_to_json(self):
        json_dict = self.chassis.to_json()
        self.assertEqual(json_dict['name'], "Test")
        self.assertEqual(json_dict['serial_number'], "1234")
        self.assertEqual(json_dict['description'], "Awesome chassis")
        self.assertEqual(len(json_dict['modules']), 1)
        module = json_dict['modules'][0]
        self.assertEqual(module['name'], "module")
        self.assertEqual(module['part_number'], "part1")

    def test_to_json_safe(self):
        json_dict = self.chassis.to_json()
        json_dict['name'] = "New name"
        self.assertEqual(json_dict['name'], "New name")
        self.assertEqual(self.chassis.name, "Test")

class ChassisModuleTest(unittest.TestCase):
    def setUp(self):
        module = ChassisModule()
        module.name="FPC"
        module.version="REV 02"
        module.part_number="part1"
        module.description="Sweet module"
        module.model_number="FPC-1-D"
        module.clei_code="1234567890"

        submod = ChassisModule()
        submod.name="PIC 0"
        submod.version="REV 13"
        submod.part_number="772-TEST"
        submod.serial_number="SOMEID1"
        submod.description="SNG PMB"

        subsubmod = ChassisModule()
        subsubmod.name="Xcvr 0"

        submod.sub_modules.append(subsubmod)

        module.sub_modules.append(submod)
        self.module = module

    def test_to_json(self):
        jmod = self.module.to_json()
        self.assertEqual(jmod['name'], "FPC")
        self.assertEqual(jmod['version'], "REV 02")
        self.assertEqual(jmod['part_number'], "part1")
        self.assertEqual(jmod['description'], "Sweet module")
        self.assertEqual(jmod['model_number'], "FPC-1-D")
        self.assertEqual(jmod['clei_code'], "1234567890")
        self.assertEqual(len(jmod['sub_modules']), 1)
        
        submod = jmod['sub_modules'][0]
        self.assertEqual(submod['name'], "PIC 0")
        self.assertEqual(submod['version'], "REV 13")
        self.assertEqual(submod['part_number'], "772-TEST")
        self.assertEqual(submod['serial_number'], "SOMEID1")
        self.assertEqual(submod['description'], "SNG PMB")

        self.assertEqual(len(submod['sub_modules']), 1)
        self.assertEqual(submod['sub_modules'][0]['name'], "Xcvr 0")
    
    def test_to_json_safe(self):
        jmod = self.module.to_json()
        jmod['name'] = "other name"
        self.assertEqual(jmod['name'], "other name")
        self.assertEqual(self.module.name, "FPC")
