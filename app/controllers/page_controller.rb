class PageController < ApplicationController
   require 'diff/lcs/hunk'

  def handle
    session[:link_back] = nil
    @path = params[:path]

    # is it a file?
    if !@path.empty? and @path.last.match(/[\w-]+\.\w+/)
      process_file
      return
    end

    @page = Page.find_by_path(@path)
    if @page.nil?
      unless @current_user.logged?
        unprivileged
      else
        params.include?('create') ? create : new
      end
      return
    end

    # manager actions
    if @current_user.can_manage_page? @page
      if params.include? 'manage' then render :action => :manage and return
      elsif params.include? 'change-permission' then change_permission and return
      elsif params.include? 'set-permissions' then set_permissions and return
      elsif params.include? 'remove-permission' then remove_permission and return
      elsif params.include? 'switch-public' then switch_public and return
      elsif params.include? 'switch-editable' then switch_editable and return
      end
    end

    # editor actions
    if @current_user.can_edit_page? @page
      if params.include? 'edit' then edit and return
      elsif params.include? 'update' then update and return
      elsif params.include? 'upload' then upload and return
      elsif params.include? 'undo' then undo and return
      elsif params.include? 'new-part' then new_part and return
      elsif params.include? 'files' then files and return
      end
    end

    # for logged user
    if @current_user.logged?
      if params.include? 'groups' then groups and return end
    end

    # viewer actions
    if params.include? 'rss'
      user_from_token = User.find_by_token params[:token]
      user_from_token = AnonymousUser.new if user_from_token.nil?
      if user_from_token.can_view_page? @page
        rss_history
      else
        render :nothing => true, :status => :forbidden
      end
      return
    end

    if @current_user.can_view_page? @page
      if params.include? 'history' then render :action => :show_history and return
      elsif params.include? 'revision' then show_revision and return
      elsif params.include? 'diff' then diff and return
      else view #and return
      end
    else
      unprivileged
    end
  end

  def view
    link = request.env['PATH_INFO']
    unless link.ends_with?('/')
      redirect_to link + '/'
      return
    end
    @hide_view_in_toolbar = true
    layout = @page.nil? ? 'application' : @page.resolve_layout
    render :action => :view, :layout => layout
  end

  def unprivileged
    @hide_view_in_toolbar = true
    render :action => :unprivileged
  end

  def diff
    @page = PageAtRevision.find_by_path(@path)
       if (params[:first_revision].to_i < params[:second_revision].to_i)
         first = params[:second_revision]
         second = params[:first_revision]
       else
         second = params[:second_revision]
         first = params[:first_revision]
       end

       @page.revision_date = @page.page_parts_revisions[first.to_i].created_at
       @first_revision = @page.get_page_parts_by_date(first)
           old_revision = ""
           for part in @first_revision
             unless part.was_deleted
               old_revision<< part.body << "\n"
             end
           end
       @page.revision_date = @page.page_parts_revisions[second.to_i].created_at
       @second_revision = @page.get_page_parts_by_date(second)
           new_revision = ""
           for part in @second_revision
             unless part.was_deleted
               new_revision<< part.body << "\n"
             end
           end
       compare(old_revision, new_revision)
       render :action => 'diff'
  end
     
 def compare old,new
   @output = []
     data_old = old.split(/\n/).map! { |e| e.chomp }
     data_new = new.split(/\n/).map! { |e| e.chomp }
     diffs = Diff::LCS.sdiff(data_old, data_new)
     puts "*****************************************************************************************"
     #p diffs

    for diff in diffs
       data_old_parse = ""
       data_new_parse = ""
       temp = []
      if((diff.action == '=')||(diff.action == '-')||(diff.action == '+'))
        begin
          if(diff.action == '-')

            @output << [diff.action, diff.old_element]
          else
            @output << [diff.action, diff.new_element]
          end
        end
      else begin
              data_old_parse = diff.old_element.split(" ").map! { |e| e.chomp }
              data_new_parse = diff.new_element.split(" ").map! { |e| e.chomp }
              diffs_parsed = Diff::LCS.sdiff(data_old_parse, data_new_parse)
                 for parsed_diff in diffs_parsed
                   case parsed_diff.action
                         when '=' then temp << ['=', parsed_diff.old_element]
                         when '-' then temp << ['-', parsed_diff.old_element]
                         when '+' then temp << ['+', parsed_diff.new_element]
                   end
                 end
               @output << ['*',temp]
               end
        end
     p @output
    end
  end
   
  def pagesib
     @current = @page.get_page(params[:id].to_i).first
      render :action =>'page_siblings'
  end
  
  def show_revision
    @page = PageAtRevision.find_by_path(@path)
    @page.revision_date = @page.page_parts_revisions[params[:revision].to_i].created_at
    @page_parts = @page.get_page_parts_by_date(params[:revision])
    layout = @page.nil? ? 'application' : @page.resolve_layout
    render :action => 'show_revision', :layout => layout  
  end

  def undo
    @page_revision = @page.page_parts_revisions[params[:revision].to_i]
    @page_part = @page_revision.page_part
    @undo = true
    render :action => 'edit'
  end

  def switch_public
    was_public = @page.is_public?
    if(@page.parent.nil? || @page.parent.is_public?)
      @page.page_permissions.each do |permission|
        permission.can_view = was_public
        permission.can_edit = was_public if was_public
        #TODO: if the @page has some public descendants, we should spread the switch to them as well
        permission.save
      end
    end
    redirect_to @page.get_path + "?manage"
  end
  
  def switch_editable
    was_editable = @page.is_editable?
    if(@page.parent.nil? || @page.parent.is_public?)
      @page.page_permissions.each do |permission|
        permission.can_view = was_editable if !was_editable
        permission.can_edit = was_editable
        #TODO: if the @page has some public descendants, we should spread the switch to them as well
        permission.save
      end
    end
    redirect_to @page.get_path + "?manage"
  end

  def change_permission
    page_permission = @page.page_permissions[params[:index].to_i]
    if(params[:permission] == "can_view")
      if(page_permission.group.users.include? @current_user)
        flash[:notice] = "You cannot disable your own view permission if you are in the manager group of the page. If you want to make this page public, you should use the quick setup link below"
      else
        page_permission.can_view ? @page.remove_viewer(page_permission.group):@page.add_viewer(page_permission.group)
      end
    elsif(params[:permission] == "can_edit")
      if(page_permission.group.users.include? @current_user)
        flash[:notice] = "You cannot disable your own edit permission if you are in the manager group of the page. If you want to make this page editable by anyone, you should use the quick setup link below"
      else
        page_permission.can_edit ? @page.remove_editor(page_permission.group):@page.add_editor(page_permission.group)
      end
    elsif(params[:permission] == "can_manage")
      page_permission.can_manage ? @page.remove_manager(page_permission.group):@page.add_manager(page_permission.group)
    end
    page_permission.save
    redirect_to @page.get_path + "?manage"
  end

  def remove_permission
    page_permission = @page.page_permissions[params[:index].to_i]
    page_permission.destroy
    redirect_to @page.get_path + "?manage"
  end

  def process_file
    @no_toolbar = true
    file_name = 'shared/upload/' + @path.join('/')
    parent_page_path = @path.clone
    @filename = parent_page_path.pop
    @page = Page.find_by_path(parent_page_path)

    if params.include? 'upload' then upload and return
    end
    return render(:action => :file_not_found) unless File.file?(file_name)
    
    if @current_user.can_view_page? @page
      return send_file(file_name)
    else
      return render(:action => :unprivileged)
    end
  end

  def new
    if @path.empty?
      @parent_id = nil
    else
      parent_path = Array.new @path
      parent_path.pop
      parent = Page.find_by_path(parent_path)
      render :action => 'no_parent' and return if parent.nil?
      @parent_id = parent.id
    end
    if(!@parent_id.nil? && !(@current_user.can_edit_page? Page.find_by_id(@parent_id)))
      unprivileged 
    else
      @sid = @path.empty? ? nil : @path.last
      render :action => 'new'
    end
  end

  def create
    parent = nil
    unless params[:parent_id].blank?
      parent = Page.find_by_id(params[:parent_id])
      # TODO check if exists
    end

    if(!parent.nil? && !(@current_user.can_edit_page? parent))
      unprivileged
    else
      sid = params[:sid].blank? ? nil : params[:sid]
      layout = params[:layout].empty? ? nil : params[:layout]
      page = Page.new(:title => params[:title], :sid => sid, :layout => layout)
      unless (page.valid?)
        error_message = ""
        page.errors.each_full { |msg| error_message << msg }
        flash[:notice] = error_message
        render :action => "new"
        return
      end
      page.save!
      page.add_manager @current_user.private_group
      page.move_to_child_of parent unless parent.nil?
      page_part = PagePart.create(:name => "body", :page => page, :current_page_part_revision_id => 0)
      first_revision = PagePartRevision.new(:user => @current_user, :body => params[:body], :page_part => page_part, :summary => params[:summary])
      unless (first_revision.valid?)
        error_message = ""
        first_revision.errors.each_full { |msg| error_message << msg }
        flash[:notice] = error_message
        @body = first_revision.body
        @sid = sid
        @parent_id = params[:parent_id]
        page_part.delete
        page.delete
        render :action => "new"
        return
      end
      if(first_revision.save)
        flash[:notice] = 'Page successfully created.'
        page_part.current_page_part_revision = first_revision
        page_part.save!
      end
      redirect_to page.get_path
    end
  end

  def show_history
    if params.include? 'diff'
      render :action => "diff"
    end
  end

  def rss_history
    @recent_revisions = PagePartRevision.find(:all, :include => [:page_part, :user], :conditions => ["page_parts.page_id = ?", @page.id], :limit => 10, :order => "created_at DESC")
    @revision_count = @page.page_parts_revisions.count
    render :action => :rss_history, :layout => false
  end

  private
  def edit
    render :action => :edit
  end

  def set_permissions
   addedgroups =  params[:add_group].split(",")
       for addedgroup in addedgroups
         groups = Group.find_all_by_name(addedgroup)
          for group in groups
            @page.add_viewer group if params[:can_view]
            @page.add_editor group if params[:can_edit]
            @page.add_manager group if params[:can_manage]
          end
       end
        redirect_to @page.get_path + "?manage"
  end

  def update
     @page.title = params[:title]
     if @current_user.can_manage_page? @page
       @page.layout = params[:layout].empty? ? nil : params[:layout]
     end
     @page.save
     params[:parts].each do |part_name, body|
       page_part = PagePart.find_by_name_and_page_id(part_name, @page.id)
       s = "page_part_name_" + part_name
       current_revision = page_part.current_page_part_revision
       params[s]
       page_part
        revision = nil
       if(params[s] != part_name || page_part.current_page_part_revision.body != body ||
             current_revision.was_deleted && (params[:is_deleted].blank? || params[:is_deleted][part_name].blank?) ||
             !current_revision.was_deleted && !params[:is_deleted].blank? && !params[:is_deleted][part_name].blank?)

         revision = PagePartRevision.new(:user => @current_user, :page_part => page_part, :body => body, :summary => params[:summary])
         if(!current_revision.was_deleted && (!params[:is_deleted].blank? && !params[:is_deleted][part_name].blank?))
           revision.was_deleted = true
         end
         unless(revision.valid?)
           error_message = ""
           revision.errors.each_full { |msg| error_message << msg }
           @page_part = page_part
           @page_revision = revision
           flash[:error] = error_message
           render :action => "edit"
           return true
         end
         revision.save!
         page_part.current_page_part_revision = revision
         page_part.name = params[s]
         page_part.save!
       end
     end
     flash[:notice] = 'Page successfully updated.'
     redirect_to @page.get_path
   end

   def new_part
    page_part = @page.page_parts.find_by_name(params[:new_page_part_name])
    page_part = PagePart.create(:name => params[:new_page_part_name], :page => @page, :current_page_part_revision_id => 0) if page_part.nil?
     unless page_part.valid?
       error_message = ""
       page_part.errors.each_full { |msg| error_message << msg }
       flash[:error] = error_message
       render :action => "edit"
       return true
     end
     page_part_revision = PagePartRevision.new(:user => @current_user, :page_part => page_part, :body => params[:new_page_part_text], :summary => "init")
     page_part_revision.save
     page_part.current_page_part_revision = page_part_revision
     page_part.save!
     flash[:notice] = 'Page part successfully added.'
     redirect_to @page.get_path + "?edit"
   end

  def upload
    @uploaded_file = UploadedFile.new(params[:uploaded_file])
    sleep(2)
    @name = params[:uploaded_file_filename]
    if !@name.nil? && File.extname(@name) != File.extname(@uploaded_file.filename)
      flash[:notice] = 'Type of file not match. No file uploaded.'
      redirect_to @page.get_path
    else
      @uploaded_file.page = @page
      @uploaded_file.user = @current_user
      @uploaded_file.rename(@name) unless @name.nil?
      if @uploaded_file.save
        flash[:notice] = 'File was successfully uploaded.'
        redirect_to @page.get_path
      else
        error_message = ""
        @uploaded_file.errors.each_full { |msg| error_message << msg }
        flash[:notice] = error_message
        render :action => :edit
      end
      end
    end
    
  def files
    render :action => :files
  end

  def groups
    @page = Page.find_by_path(@path)
    session[:link_back] = @page.get_path
    redirect_to groups_path
    end
end