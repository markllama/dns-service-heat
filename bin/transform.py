#!/usr/bin/env python
#
# 
#
import sys,os,yaml

from jinja2 import Environment, FileSystemLoader

template = Environment(loader=FileSystemLoader(os.getcwd())).get_template(sys.argv[1])

print template.render(yaml.load(sys.stdin))


        
