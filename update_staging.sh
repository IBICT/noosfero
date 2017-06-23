#!/bin/bash

git checkout master
git pull
git stash
git checkout staging
git pull
git merge --strategy-option theirs
git push 
