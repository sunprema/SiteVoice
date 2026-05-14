defmodule Sitevoice.Test.ExAwsMock do
  @moduledoc false

  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(:get, url, _body, _headers, _opts) do
    send(self(), {:ex_aws_request, :get, url, ""})
    {:ok, %{status_code: 200, headers: [], body: "data"}}
  end

  def request(method, url, body, _headers, _opts) do
    send(self(), {:ex_aws_request, method, url, body})
    {:ok, %{status_code: 200, headers: [], body: body}}
  end
end
