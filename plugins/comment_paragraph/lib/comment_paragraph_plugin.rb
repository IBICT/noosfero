class CommentParagraphPlugin < Noosfero::Plugin

  def self.plugin_name
    "Comment Paragraph"
  end

  def self.plugin_description
    _("A plugin that display comments divided by paragraphs.")
  end

  def unavailable_comments(scope)
    scope.without_paragraph
  end

  def comment_form_extra_contents(args)
    comment = args[:comment]
    paragraph_uuid = comment.paragraph_uuid || args[:paragraph_uuid]
    proc {
      arr = []
      arr << hidden_field_tag('comment[id]', comment.id)
      arr << hidden_field_tag('comment[paragraph_uuid]', paragraph_uuid) if paragraph_uuid
      arr << hidden_field_tag('comment[comment_paragraph_selected_area]', comment.comment_paragraph_selected_area) unless comment.comment_paragraph_selected_area.blank?
      arr << hidden_field_tag('comment[comment_paragraph_selected_content]', comment.comment_paragraph_selected_content) unless comment.comment_paragraph_selected_content.blank?
      arr
    }
  end

  def comment_extra_contents(args)
    comment = args[:comment]
    proc {
      render :file => 'comment/comment_extra', :locals => {:comment => comment}
    }
  end

  def js_files
    ['comment_paragraph_macro', 'rangy-core', 'rangy-cssclassapplier', 'rangy-serializer']
  end

  def stylesheet?
    true
  end

end

require_dependency 'comment_paragraph_plugin/macros/allow_comment'
