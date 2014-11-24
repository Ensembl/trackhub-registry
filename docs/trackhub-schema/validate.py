#!/usr/bin/env python

import sys
import getopt
import json
from jsonschema import Draft4Validator
# from pprint import pprint

def main(argv):
    (schema, instance) = ('','')
    try:                                
        opts, args = getopt.getopt(argv, "hs:f:")
    except getopt.GetoptError:          
        usage()                         
        sys.exit(2)                     
    for opt, arg in opts:
        if opt == '-h':
            usage()     
            sys.exit()
        elif opt == '-s':
            with open(arg) as json_file:
                schema = json.load(json_file)
        elif opt == '-f':
            with open(arg) as json_file:
                instance = json.load(json_file)

    if not schema or not instance:
        usage()
        sys.exit(2)

    v = Draft4Validator(schema)
    errors = sorted(v.iter_errors(instance), key=lambda e: e.path)
    for error in errors:
        print(error)
        # print(error.message)
        # print(list(error.path))
        for suberror in sorted(error.context, key=lambda e: e.schema_path):
            print(list(suberror.schema_path), suberror.message)    


def usage():
    print "validate.py\n[options]\n\t-s <schema>\n\t-f <file>\n"

if __name__ == "__main__":
    main(sys.argv[1:])
