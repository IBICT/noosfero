Airbrake.configure do |config|
  config.api_key = '50c752b287f566a31e2adc9e84e379bc'
  config.host    = 'diagnostico.participa.br'
  config.port    = 80
  config.secure  = config.port == 443
end
