module Noosfero
  PROJECT = 'noosfero'
  VERSION = '1.1~rc1'
end

if File.exist?(File.join(Rails.root, '.git'))
  Noosfero::VERSION.clear << Dir.chdir(Rails.root) { `git describe --tags`.strip }
end
