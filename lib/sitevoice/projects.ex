defmodule Sitevoice.Projects do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Projects.Project
    resource Sitevoice.Projects.Project.Version
    resource Sitevoice.Projects.ProjectMembership
  end
end
