class CustomFormsPlugin::Form < ApplicationRecord

  belongs_to :profile

  has_many :fields, -> { order 'position' },
    class_name: 'CustomFormsPlugin::Field', dependent: :destroy
  accepts_nested_attributes_for :fields, :allow_destroy => true

  has_many :submissions,
    :class_name => 'CustomFormsPlugin::Submission', :dependent => :destroy

  serialize :access

  validates_presence_of :profile, :name, :identifier
  validates_uniqueness_of :slug, :scope => :profile_id
  validates_uniqueness_of :identifier, :scope => :profile_id
  validate :period_range,
    :if => Proc.new { |f| f.begining.present? && f.ending.present? }
  validate :access_format

  # We are using a belongs_to relation, to avoid change the UploadedFile schema.
  # With the belongs_to instead of the has_one, we keep the change only on the
  # CustomFormsPlugin::Form schema.
  belongs_to :article, :class_name => 'UploadedFile', dependent: :destroy

  attr_accessible :name, :profile, :for_admission, :access, :begining
  attr_accessible :ending, :description, :fields_attributes, :profile_id
  attr_accessible :on_membership, :identifier

  before_validation do |form|
    form.slug = form.name.to_slug if form.name.present?
    form.access = nil if form.access.blank?
  end

  after_destroy do |form|
    tasks = CustomFormsPlugin::MembershipSurvey.opened.select { |t| t.form_id == form.id }
    tasks.each {|task| task.cancel}
  end

  scope :from_profile, -> profile { where profile_id: profile.id }
  scope :on_memberships, -> { where on_membership: true, for_admission: false }
  scope :for_admissions, -> { where for_admission: true }
=begin
  scope :accessible_to lambda do |profile|
    #TODO should verify is profile is associated with the form owner
    profile_associated = ???
    {:conditions => ["
      access IS NULL OR
      (access='logged' AND :profile_present) OR
      (access='associated' AND :profile_associated) OR
      :profile_id in access
    ", {:profile_present => profile.present?, :profile_associated => ???, :profile_id => profile.id}]}
  end
=end

  def expired?
    (begining.present? && Time.now < begining) || (ending.present? && Time.now > ending)
  end

  def will_open?
    begining.present? && Time.now < begining
  end

  def accessible_to(target)
    return true if access.nil? || target == profile
    return false if target.nil?
    return true if access == 'logged'
    return true if access == 'associated' && ((profile.organization? && profile.members.include?(target)) || (profile.person? && profile.friends.include?(target)))
    return true if access.kind_of?(Integer) && target.id == access
    return true if access.kind_of?(Array) && access.include?(target.id)
  end

  def image
    self.article
  end

  def image=(uploaded_file)
    self.article = uploaded_file
  end

  private

  def access_format
    if access.present?
      if access.kind_of?(String)
        if access != 'logged' && access != 'associated'
          errors.add(:access, _('Invalid string format of access.'))
        end
      elsif access.kind_of?(Integer)
        if !Profile.exists?(access)
          errors.add(:access, _('There is no profile with the provided id.'))
        end
      elsif access.kind_of?(Array)
        access.each do |value|
          if !value.kind_of?(Integer) || !Profile.exists?(value)
            errors.add(:access, _('There is no profile with the provided id.'))
            break
          end
        end
      else
        errors.add(:access, _('Invalid type format of access.'))
      end
    end
  end

  def period_range
    errors.add(:base, _('The time range selected is invalid.')) if ending < begining
  end
end
