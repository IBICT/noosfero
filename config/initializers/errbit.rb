Airbrake.configure do |config|
  config.api_key = 'ce6eb32b85f36bd5509ea8db8754a8f3'
  config.host    = 'diagnostico.participa.br'
  config.port    = 80
  config.secure  = config.port == 443
end
