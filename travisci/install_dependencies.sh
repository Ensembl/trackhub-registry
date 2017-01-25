#!/bin/bash

cpanm -v --installdeps --notest $PWD/src/Registry
cpanm -n Devel::Cover::Report::Coveralls
