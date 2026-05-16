defmodule Sitevoice.Projects do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Projects.Project do
      define :get_project, action: :read, get_by: [:id]
      define :create_project, action: :create
      define :list_projects, action: :list_active
    end

    resource Sitevoice.Projects.Project.Version

    resource Sitevoice.Projects.ProjectMembership do
      define :add_member, action: :add_member
      define :list_project_memberships, action: :list_for_project, args: [:project_id]
      define :update_membership_role, action: :update_role
      define :remove_membership, action: :remove_member
    end
  end
end
