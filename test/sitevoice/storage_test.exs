defmodule Sitevoice.StorageTest do
  use ExUnit.Case, async: true

  @moduletag slice: :foundation

  describe "store/3" do
    test "returns {:ok, key} on success" do
      assert {:ok, "some/key.bin"} = Sitevoice.Storage.store("test-bucket", "some/key.bin", "data")
      assert_received {:ex_aws_request, :put, _url, "data"}
    end
  end

  describe "fetch/2" do
    test "returns {:ok, body} on success" do
      assert {:ok, "data"} = Sitevoice.Storage.fetch("test-bucket", "some/key.bin")
      assert_received {:ex_aws_request, :get, _url, _body}
    end
  end

  describe "presigned_url/3" do
    test "returns {:ok, url} with a valid presigned URL" do
      assert {:ok, url} = Sitevoice.Storage.presigned_url("test-bucket", "some/key.bin", 3600)
      assert String.starts_with?(url, "https://")
      assert String.contains?(url, "some%2Fkey.bin") or String.contains?(url, "some/key.bin")
    end
  end
end
