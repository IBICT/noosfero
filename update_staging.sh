#!/bin/bash

git checkout master
git pull
git checkout staging
git pull
git merge --strategy-option theirs
git push 
