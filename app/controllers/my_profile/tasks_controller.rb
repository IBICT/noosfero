class TasksController < MyProfileController

  include TasksHelper

  protect [:perform_task, :view_tasks], :profile, :only => [:index, :save_tags, :search_tags]
  protect :perform_task, :profile, :except => [:index, :save_tags, :search_tags]
  helper CustomFieldsHelper

  def index
    @rejection_email_templates = profile.email_templates.where template_type: :task_rejection
    @acceptance_email_templates = profile.email_templates.where template_type: :task_acceptance

    @filter_type = params[:filter_type].presence
    @filter_text = params[:filter_text].presence
    @filter_responsible = params[:filter_responsible]
    @filter_tags = params[:filter_tags]

    @task_types = Task.pending_types_for(profile)
    @task_tags = [OpenStruct.new(:name => _('All'), :id => nil) ] + Task.all_tags

    @tasks = Task.pending_all(profile, @filter_type, @filter_text).order_by('created_at', 'asc').paginate(:per_page => Task.per_page, :page => params[:page])
    @tasks = @tasks.where(:responsible_id => @filter_responsible.to_i != -1 ? @filter_responsible : nil) if @filter_responsible.present?
    @tasks = @tasks.tagged_with(@filter_tags, any: true) if @filter_tags.present?
    @tasks = @tasks.paginate(:per_page => Task.per_page, :page => params[:page])
    @failed = params ? params[:failed] : {}

    @responsible_candidates = profile.members.by_role(profile.roles.reject {|r| !r.has_permission?('perform_task') && !r.has_permission?('view_tasks')}) if profile.organization?

    @view_only = !current_person.has_permission?(:perform_task, profile)

  end

  def processed
    @tasks = Task.to(profile).without_spam.closed.order('tasks.created_at DESC')
    @filter = params[:filter] || {}
    @tasks = filter_tasks(@filter, @tasks)
    @tasks = @tasks.paginate(:per_page => Task.per_page, :page => params[:page])
    @task_types = Task.closed_types_for(profile)
  end

  def change_responsible
    task = profile.tasks.find(params[:task_id])

    if task.responsible.present? && task.responsible.id != params[:old_responsible_id].to_i
      return render :json => {:notice => _('Task already assigned!'), :success => false, :current_responsible => task.responsible.id}
    end

    responsible = profile.members.find(params[:responsible_id]) if params[:responsible_id].present?
    task.responsible = responsible
    task.save!
    render :json => {:notice => _('Task responsible successfully updated!'), :success => true, :new_responsible => {:id => responsible.present? ? responsible.id : nil}}
  end

  VALID_DECISIONS = [ 'finish', 'cancel', 'skip' ]

  def close
    failed = {}
    save = false

    if params[:tasks]
      params[:tasks].each do |id, value|
        decision = value[:decision]

        if value[:task].is_a?(Hash) && value[:task][:tag_list]

          task = profile.find_in_all_tasks(id)
          task.tag_list = value[:task][:tag_list]
          value[:task].delete('tag_list')

          save = true
        end

        if request.post?
          if VALID_DECISIONS.include?(decision) && id && decision != 'skip'
            task ||= profile.find_in_all_tasks(id)
            begin
              task.update(value[:task])
              task.send(decision, current_person)
            rescue Exception => ex
              message = "#{task.title} (#{task.requestor ? task.requestor.name : task.author_name})"
              failed[ex.message] ? failed[ex.message] << message : failed[ex.message] = [message]
            end
          elsif save
            task.save!
          end
        end
      end
    end

    url = tasks_url(:action => 'index')
    if failed.blank?
      session[:notice] = _("All decisions were applied successfully.")
    else
      session[:notice] = _("Some decisions couldn't be applied.")
      url = tasks_url(:action => 'index', :failed => failed)
    end
    redirect_to url
  end

  def new
    @ticket = Ticket.new(params[:ticket])
    if params[:target_id]
      @ticket.target = profile.friends.find(params[:target_id])
    end
    @ticket.requestor = profile
    if request.post?
      if @ticket.save
        redirect_to :action => 'index'
      end
    end
  end

  def list_requested
    @tasks = Task.without_spam.where requestor_id: profile.id
  end

  def ticket_details
    @ticket = Ticket.where('(requestor_id = ? or target_id = ?) and id = ?', profile.id, profile.id, params[:id]).first
  end

  def search_tasks
    filter_type = params[:filter_type].presence
    filter_text = params[:filter_text].presence
    result = Task.pending_all(profile,filter_type, filter_text)

    render :json => result.map { |task| {:label => task.data[:name], :value => task.data[:name]} }
  end

  def save_tags
    if request.post? && params[:tag_list]
      result = {
        success: false,
        message: _('Error to save tags. Please, contact the system admin')
      }

      ActsAsTaggableOn.remove_unused_tags = true

      task = profile.tasks.find_by_id(params[:task_id])
      
      if task && task.update_attributes(:tag_list => params[:tag_list])
        result[:success] = true
      end
    end

    render json: result
  end

  # FIXME make this test
  # Should not search for article tasks
  # Should not search for other profile tags
  # Should search only task tags
  # Should check the permissions

  def search_tags

    arg = params[:term].downcase

    result = ActsAsTaggableOn::Tag.find(:all, :conditions => ['LOWER(name) LIKE ?', "%#{arg}%"])

    render :text => prepare_to_token_input_by_label(result).to_json, :content_type => 'application/json'
  end

  protected

  def filter_tasks(filter, tasks)
    tasks = tasks.eager_load(:requestor, :closed_by)
    tasks = tasks.of(filter[:type].presence)
    tasks = tasks.where(:status => filter[:status]) unless filter[:status].blank?

    filter[:created_from] = Date.parse(filter[:created_from]) unless filter[:created_from].blank?
    filter[:created_until] = Date.parse(filter[:created_until]) unless filter[:created_until].blank?
    filter[:closed_from] = Date.parse(filter[:closed_from]) unless filter[:closed_from].blank?
    filter[:closed_until] = Date.parse(filter[:closed_until]) unless filter[:closed_until].blank?

    tasks = tasks.from_creation_date filter[:created_from] unless filter[:created_from].blank?
    tasks = tasks.until_creation_date filter[:created_until] unless filter[:created_until].blank?

    tasks = tasks.from_closed_date filter[:closed_from] unless filter[:closed_from].blank?
    tasks = tasks.until_closed_date filter[:closed_until] unless filter[:closed_until].blank?

    tasks = tasks.where('profiles.name LIKE ?', filter[:requestor]) unless filter[:requestor].blank?
    tasks = tasks.where('closed_bies_tasks.name LIKE ?', filter[:closed_by]) unless filter[:closed_by].blank?
    tasks = tasks.where('tasks.data LIKE ?', "%#{filter[:text]}%") unless filter[:text].blank?
    tasks
  end

end
