defmodule DeployexWeb.ErrorJSONTest do
  use DeployexWeb.ConnCase, async: true

  test "renders 404" do
    assert DeployexWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert DeployexWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
