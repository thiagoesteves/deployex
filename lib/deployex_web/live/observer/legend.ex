defmodule DeployexWeb.Observer.Legend do
  @moduledoc false
  use Phoenix.Component

  def content(assigns) do
    ~H"""
    <div class="p-3 border border-black relative mt-5">
      <h2 class="absolute -top-1/2 translate-y-1/2 bg-white">Legend</h2>
      <div class="flex items-center">
        <span class="text-gray-600 dark:text-neutral-600">Process (App)</span>
        <div class="w-6 h-6 bg-white mr-3 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="w-4 h-4 text-[#A1887F]"
          >
            <polygon points="12,2 22,12 12,22 2,12"></polygon>
          </svg>
        </div>

        <span class="text-gray-600 dark:text-neutral-600">Supervisor</span>
        <div class="w-6 h-6 rounded-lg bg-white mr-3 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="w-4 h-4 text-[#F87171]"
          >
            <rect x="3" y="3" width="18" height="18" rx="4" ry="4"></rect>
          </svg>
        </div>

        <span class="text-gray-600 dark:text-neutral-600">Process (Worker)</span>
        <div class="w-6 h-6 rounded-full bg-white mr-3 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="w-4 h-4 text-[#93C5FD]"
          >
            <circle cx="12" cy="12" r="8"></circle>
          </svg>
        </div>

        <span class="text-gray-600 dark:text-neutral-600">Port</span>
        <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="w-4 h-4 text-[#FBBF24]"
          >
            <polygon points="12,2 22,22 2,22"></polygon>
          </svg>
        </div>

        <span class="text-gray-600 dark:text-neutral-600">Reference</span>
        <div class="w-6 h-6 rounded-lg bg-white mr-3 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="w-4 h-4 text-[#28A745]"
          >
            <rect x="3" y="3" width="18" height="18"></rect>
          </svg>
        </div>

        <span class="text-gray-600 dark:text-neutral-600">Link</span>
        <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="w-4 h-4"
          >
            <line x1="0" y1="12" x2="24" y2="12" stroke="#CCC" stroke-width="2"></line>
          </svg>
        </div>

        <span class="text-gray-600 dark:text-neutral-600">Monitor</span>
        <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="w-4 h-4"
          >
            <line x1="0" y1="12" x2="24" y2="12" stroke="#D1A1E5" stroke-width="2"></line>
          </svg>
        </div>

        <span class="text-gray-600 dark:text-neutral-600">Monitored by</span>
        <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="w-4 h-4"
          >
            <line x1="0" y1="12" x2="24" y2="12" stroke="#4DB8FF" stroke-width="2"></line>
          </svg>
        </div>
      </div>
    </div>
    """
  end
end
