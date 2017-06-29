#!/bin/bash

git checkout master
git pull
rm Gemfile.lock
git stash
git checkout staging
git pull
git merge --strategy-option theirs
git push 
