defmodule DeployexWeb.AboutLive do
  use DeployexWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-700 flex flex-col items-center">
      <h1 class="text-5xl text-white font-bold mb-8 mt-10 animate-pulse">
        What is deployex?
      </h1>
      <p class="text-white text-lg mb-8 ml-5 mr-5">
        Deployex is a lightweight tool designed for managing deployments in Elixir applications
        without relying on additional deployment tools like Docker or Kubernetes. Its primary goal
        is to utilize the mix release package for executing full deployments or hot-upgrades,
        depending on the package's content, while leveraging OTP distribution for monitoring and
        data extraction. Deployex acts as a central deployment runner, gathering crucial deployment
        data such as the current version and release package contents. The content of the release
        package enables it to run for a full deployment or a hot-upgrade. Meanwhile, on the
        evelopment front, your CI/CD pipeline takes charge of crafting and updating packages
        for the target release. This integration ensures that Deployex is always equipped with
        the latest packages, ready to facilitate deployments. If you wanna know more about it,
        please visit:
        <a
          href="https://github.com/thiagoesteves/deployex"
          class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
        >
          deployex github repository
        </a>
      </p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
