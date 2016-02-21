class CommentClassificationPlugin::Status < ActiveRecord::Base

  belongs_to :owner, :polymorphic => true

  validates_presence_of :name

  scope :enabled, -> { where enabled: true }

end
