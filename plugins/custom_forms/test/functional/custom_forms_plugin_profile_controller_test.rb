require 'test_helper'

class CustomFormsPluginProfileControllerTest < ActionController::TestCase
  def setup
    @profile = create_user('profile').person
    login_as(@profile.identifier)
    environment = Environment.default
    environment.enable_plugin(CustomFormsPlugin)
  end

  attr_reader :profile

  should 'save submission if fields are ok' do
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :identifier => 'free-software')
    field1 = CustomFormsPlugin::TextField.create(:name => 'Name', :form => form, :mandatory => true)
    field2 = CustomFormsPlugin::TextField.create(:name => 'License', :form => form)

    assert_difference 'CustomFormsPlugin::Submission.count', 1 do
      post :show, :profile => profile.identifier, :id => form.identifier, :submission => {field1.id.to_s => 'Noosfero', field2.id.to_s => 'GPL'}
    end
    refute session[:notice].include?('not saved')
    assert_redirected_to :action => 'show'
  end

  should 'save submission if fields are ok and user is not logged in' do
    logout
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :identifier => 'free-software')
    field = CustomFormsPlugin::TextField.create(:name => 'Name', :form => form)

    assert_difference 'CustomFormsPlugin::Submission.count', 1 do
      post :show, :profile => profile.identifier, :id => form.identifier, :author_name => "john", :author_email => 'john@example.com', :submission => {field.id.to_s => 'Noosfero'}
    end
    assert_redirected_to :action => 'show'
  end

  should 'display errors if user is not logged in and author_name is not uniq' do
    logout
    form = CustomFormsPlugin::Form.create(:profile => profile, :name => 'Free Software', :identifier => 'free-software')
    field = CustomFormsPlugin::TextField.create(:name => 'Name', :form => form)
    submission = CustomFormsPlugin::Submission.create(:form => form, :author_name => "john", :author_email => 'john@example.com')

    assert_no_difference 'CustomFormsPlugin::Submission.count' do
      post :show, :profile => profile.identifier, :id => form.identifier, :author_name => "john", :author_email => 'john@example.com', :submission => {field.id.to_s => 'Noosfero'}
    end
    assert_equal "Submission could not be saved", session[:notice]
    assert_tag :tag => 'div', :attributes => { :class => 'errorExplanation', :id => 'errorExplanation' }
  end

  should 'disable fields if form expired' do
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :begining => Time.now + 1.day, :identifier => 'free-software')
    form.fields << CustomFormsPlugin::TextField.create(:name => 'Field Name', :form => form, :default_value => "First Field")

    get :show, :profile => profile.identifier, :id => form.identifier

    assert_tag :tag => 'input', :attributes => {:disabled => 'disabled'}
  end

  should 'show expired message' do
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :begining => Time.now + 1.day, :identifier => 'free-software')
    form.fields << CustomFormsPlugin::TextField.create(:name => 'Field Name', :form => form, :default_value => "First Field")

    get :show, :profile => profile.identifier, :id => form.identifier

    assert_tag :tag => 'h2', :content => 'Sorry, you can\'t fill this form yet'

    form.begining = Time.now - 2.days
    form.ending = Time.now - 1.days
    form.save

    get :show, :profile => profile.identifier, :id => form.identifier

    assert_tag :tag => 'h2', :content => 'Sorry, you can\'t fill this form anymore'
  end

  should 'show query review page' do

    form = CustomFormsPlugin::Form.create!(:profile => profile,
                                            :name => 'Free Software',
                                            :identifier => 'free')
    submission = CustomFormsPlugin::Submission.create!(:form => form,
                                                       :profile => profile)
    radio_field = CustomFormsPlugin::Field.create!(
      :name => 'What is your favorite food?',
      :form => form,
      :show_as => 'radio'
    )


    CustomFormsPlugin::Alternative.create!(:field => radio_field,
                                           :label => 'rice')
    CustomFormsPlugin::Alternative.create!(:field => radio_field,
                                           :label => 'beans')

    alt = CustomFormsPlugin::Alternative.create!(:field => radio_field,
                                                 :label => 'bread')

    CustomFormsPlugin::Answer.create!(:field => radio_field,
                                      :value => alt.id,
                                      :submission => submission)

    get :review, :profile => profile.identifier, :id => form.identifier

    assert_tag :tag => 'h4', :attributes => {:class => 'review_text_align'},
               :content => /What is your favorite food?/
    assert_tag :tag => 'table', :attributes => { :class => 'results-table' },
               :descendant => { :tag => 'td', :content => /bread/ }
  end

  should 'define filters default values' do
    get :queries, :profile => profile.identifier
    assert_equal 'recent', assigns(:order)
    assert_equal 'all', assigns(:kind)
    assert_equal 'all', assigns(:status)
  end

  should 'order forms' do
    survey1 = CustomFormsPlugin::Form.new(:profile => profile, :name => 'Survey 1', :identifier => 'survey1')
    survey1.created_at = Time.now - 2.days
    survey1.save!
    survey2 = CustomFormsPlugin::Form.new(:profile => profile, :name => 'Survey 2', :identifier => 'survey2')
    survey2.created_at = Time.now - 1.day
    survey2.save!
    survey3 = CustomFormsPlugin::Form.new(:profile => profile, :name => 'Survey 3', :identifier => 'survey3')
    survey3.created_at = Time.now
    survey3.save!

    get :queries, :profile => profile.identifier, :order => 'older'

    assert_equivalent assigns(:forms), [survey3, survey2, survey1]
  end

  should 'filter forms by kind' do
    survey = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Survey', :identifier => 'survey', :kind => 'survey')
    poll1 = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Poll 1', :identifier => 'poll1', :kind => 'poll')
    poll2 = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Poll 2', :identifier => 'poll2', :kind => 'poll')

    get :queries, :profile => profile.identifier, :kind => 'poll'

    assert_includes assigns(:forms), poll1
    assert_includes assigns(:forms), poll2
    assert_not_includes assigns(:forms), survey
  end

  should 'filter forms by status' do
    opened_survey = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Opened Survey', :identifier => 'opened-survey', :begining => Time.now - 1.day)
    closed_survey = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Closed Survey', :identifier => 'closed-survey', :ending => Time.now - 1.day)
    to_come_survey = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'To Come Survey', :identifier => 'to-come-survey', :begining => Time.now + 1.day)

    get :queries, :profile => profile.identifier, :status => 'opened'

    assert_includes assigns(:forms), opened_survey
    assert_not_includes assigns(:forms), closed_survey
    assert_not_includes assigns(:forms), to_come_survey
  end

  should 'filter forms by query' do
    space_wars = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Space Wars', :identifier => 'space-wars')
    star_trek = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Star Trek', :identifier => 'star-trek')
    star_wars = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Star Wars', :identifier => 'star-wars')

    get :queries, :profile => profile.identifier, :q => 'star'

    assert_includes assigns(:forms), star_wars
    assert_includes assigns(:forms), star_trek
    assert_not_includes assigns(:forms), space_wars
  end

  should 'forbid access to form based on AccessLevels' do
    community = fast_create(Community)
    form = CustomFormsPlugin::Form.create!(:profile => community, :name => 'Free Software', :identifier => 'free-software', :access => AccessLevels.levels[:visitors])
    AccessLevels.expects(:can_access?).with(form.access, profile, community).returns(false)
    get :show, :profile => community.identifier, :id => form.identifier
    assert_response :forbidden
    assert_template 'shared/access_denied'
  end

  should 'allow access to form based on AccessLevels' do
    community = fast_create(Community)
    form = CustomFormsPlugin::Form.create!(:profile => community, :name => 'Free Software', :identifier => 'free-software', :access => AccessLevels.levels[:visitors])
    AccessLevels.expects(:can_access?).with(form.access, profile, community).returns(true)
    get :show, :profile => community.identifier, :id => form.identifier
    assert_response :success
    assert_template 'custom_forms_plugin_profile/show'
  end

  should 'filter forms for visitors' do
    logout
    community = fast_create(Community)
    f1 = CustomFormsPlugin::Form.create!(:name => 'For Visitors', :profile => community, :access => AccessLevels.levels[:visitors])
    f2 = CustomFormsPlugin::Form.create!(:name => 'For Logged Users', :profile => community, :access => AccessLevels.levels[:users])
    f3 = CustomFormsPlugin::Form.create!(:name => 'For Members', :profile => community, :access => AccessLevels.levels[:related])

    get :queries, :profile => community.identifier

    assert_includes assigns(:forms), f1
    assert_not_includes assigns(:forms), f2
    assert_not_includes assigns(:forms), f3
  end

  should 'filter forms for logged users' do
    community = fast_create(Community)
    f1 = CustomFormsPlugin::Form.create!(:name => 'For Visitors', :profile => community, :access => AccessLevels.levels[:visitors])
    f2 = CustomFormsPlugin::Form.create!(:name => 'For Logged Users', :profile => community, :access => AccessLevels.levels[:users])
    f3 = CustomFormsPlugin::Form.create!(:name => 'For Members', :profile => community, :access => AccessLevels.levels[:related])

    get :queries, :profile => community.identifier

    assert_includes assigns(:forms), f1
    assert_includes assigns(:forms), f2
    assert_not_includes assigns(:forms), f3
  end

  should 'filter forms for related users' do
    community = fast_create(Community)
    community.add_member(profile)
    f1 = CustomFormsPlugin::Form.create!(:name => 'For Visitors', :profile => community, :access => AccessLevels.levels[:visitors])
    f2 = CustomFormsPlugin::Form.create!(:name => 'For Logged Users', :profile => community, :access => AccessLevels.levels[:users])
    f3 = CustomFormsPlugin::Form.create!(:name => 'For Members', :profile => community, :access => AccessLevels.levels[:related])

    get :queries, :profile => community.identifier

    assert_includes assigns(:forms), f1
    assert_includes assigns(:forms), f2
    assert_includes assigns(:forms), f3
  end

  should 'allow access to results' do
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :identifier => 'free-software', :access_result_options => 'private')
    get :review, :profile => profile.identifier, :id => form.identifier
    assert_response :success
    assert_template 'custom_forms_plugin_profile/review'
  end

  should 'forbid access to results' do
    logout
    form = CustomFormsPlugin::Form.create!(:profile => profile, :name => 'Free Software', :identifier => 'free-software', :access_result_options => 'private')
    get :review, :profile => profile.identifier, :id => form.identifier
    assert_response :forbidden
    assert_template 'shared/access_denied'
  end

  should 'download csv with all submissions' do
    form = CustomFormsPlugin::Form.create!(:profile => profile,
                                            :name => 'Free Software',
                                            :identifier => 'free')
    submission = CustomFormsPlugin::Submission.create!(:form => form,
                                                       :profile => profile)
    get :review, :profile => profile.identifier, :id => form.identifier, :format => 'csv'
    assert_response :success
  end

  should 'display form options to profile admin' do
    community = fast_create(Community)
    community.add_admin(profile)
    form = community.forms.create!(name: 'Free Software')

    get :show, :profile => community.identifier, :id => form.identifier
    assert_tag tag: 'div', attributes: { class: 'custom-form-options' }
  end

  should 'display form options to environment admin' do
    community = fast_create(Community)
    community.environment.add_admin(profile)
    form = community.forms.create!(name: 'Free Software')

    get :show, :profile => community.identifier, :id => form.identifier
    assert_tag tag: 'div', attributes: { class: 'custom-form-options' }
  end

  should 'not display form options to visitors' do
    community = fast_create(Community)
    form = community.forms.create!(name: 'Free Software')

    get :show, :profile => community.identifier, :id => form.identifier
    assert_no_tag tag: 'div', attributes: { class: 'custom-form-options' }
  end
end
