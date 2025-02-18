# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-2023  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class AdminController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :projects, :only => :projects
  menu_item :plugins, :only => :plugins
  menu_item :info, :only => :info

  before_action :require_admin

  helper :queries
  include QueriesHelper
  helper :projects_queries
  helper :projects

  def index
    @no_configuration_data = Redmine::DefaultData::Loader::no_data?
  end

  def projects
    retrieve_query(ProjectQuery, false, :defaults => @default_columns_names)
    @query.admin_projects = 1
    scope = @query.results_scope

    @entry_count = scope.count
    @entry_pages = Paginator.new @entry_count, per_page_option, params['page']
    @projects = scope.limit(@entry_pages.per_page).offset(@entry_pages.offset).to_a

    render :action => "projects", :layout => false if request.xhr?
  end

  def recalculate
  end

  def do_recalculate
    error = ""

    budget_field_idx = -1
    spent_field_idx = -1
    phase_field_idx = -1
    last_spent_on_date_idx = -1
    # najdu si indexy uživatelských polí "Rozpočet (tis. Kč)" a "Vyčerpáno (tis. Kč)" a uložím si je
    ProjectCustomField.all.each do |fld|
      # poku se pole jmenuje "Rozpočet (tis. Kč)", schov8m si index
      if fld.name == "Rozpočet (tis. Kč)"
        budget_field_idx = fld.id
      end
      if fld.name == "Vyčerpáno (tis. Kč)"
        spent_field_idx = fld.id
      end
      if fld.name == "Fáze"
        phase_field_idx = fld.id
      end
      if fld.name == "Poslední náklady k datu"
        last_spent_on_date_idx = fld.id
      end
    end
    if budget_field_idx == -1 || spent_field_idx == -1 || phase_field_idx == -1 || last_spent_on_date_idx == -1
      error = "Nepodařilo se najít uživatelská pole Rozpočet (tis. Kč), Vyčerpáno (tis. Kč) nebo Fáze nebo Poslední náklady k datu."
    end

    if error == ""
      Project.all.each do |p|
        # pokud m8 projekt nastaven0 u6ivatelsk0 pole "Fáze" na hodnotu jinou, než "3 - Exekuce", tak ho přeskočím
        skip = false
        p.custom_field_values.each do |cfv|
          if cfv.custom_field_id == phase_field_idx
            if cfv.value != "3 - Exekuce"
              skip = true
            end
          end
        end
        if skip
          next
        end

        # najdu si všechny issues v projektu
        issues = Issue.where(project_id: p.id)
        # projdu všechny issues a sečtu plánovné (field_estimated_hours) a spotřebované náklady
        total_budget = 0
        total_spent = 0
        last_spent_on = nil
        issues.each do |i|
          budget = (i.estimated_hours or 0.0).round
          spent = (i.spent_hours or 0.0).round
          total_budget += budget
          total_spent += spent
          # najdi si všechny time_emtries k dané issue a v nich najdi nejnovější hodnotu spent_on, tu ulož do proměnné last_spent_on
          i.time_entries.each do |te|
            if last_spent_on == nil || te.spent_on > last_spent_on
              last_spent_on = te.spent_on
            end
          end
        end
        # uložím si do projektu
        p.custom_field_values.each do |cfv|
          if cfv.custom_field_id == budget_field_idx
            cfv.value = total_budget.to_i
          end
          if cfv.custom_field_id == spent_field_idx
            cfv.value = total_spent.to_i
          end
          if cfv.custom_field_id == last_spent_on_date_idx
            cfv.value = last_spent_on
          end
        end
        p.save!
      end
    end

    if error != ""
      flash[:error] = l(:notice_update_error) + ': ' + error
    else
      flash[:notice] = l(:notice_successful_update)
    end
    redirect_to action: :recalculate, controller: :admin
  end

  def plugins
    @plugins = Redmine::Plugin.all
  end

  # Loads the default configuration
  # (roles, trackers, statuses, workflow, enumerations)
  def default_configuration
    if request.post?
      begin
        Redmine::DefaultData::Loader::load(params[:lang])
        flash[:notice] = l(:notice_default_data_loaded)
      rescue => e
        flash[:error] = l(:error_can_t_load_default_data, ERB::Util.h(e.message))
      end
    end
    redirect_to admin_path
  end

  def test_email
    begin
      Mailer.deliver_test_email(User.current)
      flash[:notice] = l(:notice_email_sent, ERB::Util.h(User.current.mail))
    rescue => e
      flash[:error] = l(:notice_email_error, ERB::Util.h(Redmine::CodesetUtil.replace_invalid_utf8(e.message.dup)))
    end
    redirect_to settings_path(:tab => 'notifications')
  end

  def info
    @checklist = [
      [:text_default_administrator_account_changed, User.default_admin_account_changed?],
      [:text_file_repository_writable, File.writable?(Attachment.storage_path)],
      ["#{l :text_plugin_assets_writable} (./public/plugin_assets)",   File.writable?(Redmine::Plugin.public_directory)],
      [:text_all_migrations_have_been_run, !ActiveRecord::Base.connection.migration_context.needs_migration?],
      [:text_minimagick_available,     Object.const_defined?(:MiniMagick)],
      [:text_convert_available,        Redmine::Thumbnail.convert_available?],
      [:text_gs_available,             Redmine::Thumbnail.gs_available?]
    ]
  end
end
