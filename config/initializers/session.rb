require File.join(Rails.root,'app/models/session')

ActionDispatch::Reloader.to_prepare do
  ActionDispatch::Session::ActiveRecordStore.session_class = Session
end

