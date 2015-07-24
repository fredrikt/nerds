class Chassis:
    def __init__(self):
        self.name = ''
        self.serial_number = ''
        self.description = ''
        self.modules =[]
    def __str__(self):
        return "<Chassis name: {0}, description: {1}, serial_number: {2}, modules: {3}>".format(self.name,self.description, self.serial_number, len(self.modules))
    def to_json(self):
        out = vars(self)
        out['modules'] = [m.to_json() for m in self.modules]
        return out

class ChassisModule:
    def __init__(self):
        self.name=''
        self.version=''
        self.part_number=''
        self.serial_number=''
        self.description=''
        self.model_number=''
        self.clei_code=''
        self.sub_modules=[]
    def __str__(self):
        return "<ChassisModule name: {0}, description: {1}, sub_modules: {2}>".format(self.name, self.description, len(self.sub_modules))
    def to_json(self):
        out = vars(self).copy()
        out['sub_modules'] = [m.to_json() for m in self.sub_modules]
        return out


