class Kind < ActiveRecord::Base
  self.inheritance_column = 'etype'

  belongs_to :environment
  has_and_belongs_to_many :profiles

  validates_presence_of :name, :environment
  validates_uniqueness_of :name, scope: [:type, :environment]

  def add_profile(profile)
    return if profiles.include?(profile)

    if moderated
      tasks = environment.tasks.pending.where(:type => 'ApproveKind').where(:requestor => profile)
      ApproveKind.create!(
        :target => environment,
        :requestor => profile,
        :kind => self) unless tasks.any? {|task| task.kind == self}
    else
      profiles << profile
    end
  end

  def remove_profile(profile)
    return unless profiles.include?(profile)
    profiles.destroy profile
  end

  def style_class
    "#{name.to_slug}-#{type.to_slug}-kind"
  end
end
