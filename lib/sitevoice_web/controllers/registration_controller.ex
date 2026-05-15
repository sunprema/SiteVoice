defmodule SitevoiceWeb.RegistrationController do
  use SitevoiceWeb, :controller

  def new(conn, _params) do
    render(conn, :new, errors: [], params: %{})
  end

  def create(conn, %{"registration" => params}) do
    password = params["password"] || ""
    password_confirmation = params["password_confirmation"] || ""

    cond do
      String.length(password) < 8 ->
        conn
        |> put_status(422)
        |> render(:new, errors: ["Password must be at least 8 characters"], params: params)

      password != password_confirmation ->
        conn
        |> put_status(422)
        |> render(:new, errors: ["Passwords do not match"], params: params)

      true ->
        case Sitevoice.Accounts.Actions.RegisterOrganization.call(%{
               org_name: params["org_name"],
               user_email: params["email"],
               user_password: password,
               user_name: params["name"]
             }) do
          {:ok, _result} ->
            conn
            |> put_flash(:info, "Account created! Check your email to confirm before signing in.")
            |> redirect(to: ~p"/sign-in")

          {:error, error} ->
            conn
            |> put_status(422)
            |> render(:new, errors: extract_errors(error), params: params)
        end
    end
  end

  defp extract_errors(%Ash.Changeset{errors: errors}), do: Enum.map(errors, &error_message/1)
  defp extract_errors(%{errors: errors}), do: Enum.map(errors, &error_message/1)
  defp extract_errors(error), do: [to_string(error)]

  defp error_message(%{field: field, message: msg}) when not is_nil(field),
    do: "#{Phoenix.Naming.humanize(field)} #{msg}"

  defp error_message(%{message: msg}), do: msg
  defp error_message(error), do: to_string(error)
end
