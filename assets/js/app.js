// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.

// Prevent browser from restoring the previous scroll position on navigation,
// which causes a visible "bounce" before the page settles at the top.
if ("scrollRestoration" in history) {
  history.scrollRestoration = "manual"
}

import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
// import {hooks as colocatedHooks} from "phoenix-colocated/ledgr"
import topbar from "../vendor/topbar"
import TomSelect from "../vendor/tom-select.min.js"
import Chart from "../vendor/chart.umd.min.js"

// ==============================
// LiveView Hooks
// ==============================

const SearchableSelect = {
  mounted() {
    this.initTomSelect()
  },

  updated() {
    // Destroy and reinitialize if options have changed
    if (this.tomSelect) {
      this.tomSelect.destroy()
    }
    this.initTomSelect()
  },

  destroyed() {
    if (this.tomSelect) {
      this.tomSelect.destroy()
    }
  },

  initTomSelect() {
    const select = this.el.querySelector('select')
    if (!select) return

    const prompt = select.dataset.prompt || 'Search...'

    this.tomSelect = new TomSelect(select, {
      create: false,
      sortField: {
        field: "text",
        direction: "asc"
      },
      placeholder: prompt,
      allowEmptyOption: true,
      onType: function(str) {
        // Clear the current selection when the user starts typing
        // so the old value doesn't stick in the input
        if (str.length > 0 && this.items.length > 0) {
          this.clear(true)
        }
      },
      render: {
        option: function(data, escape) {
          return '<div class="option">' + escape(data.text) + '</div>'
        },
        item: function(data, escape) {
          return '<div class="item">' + escape(data.text) + '</div>'
        },
        no_results: function(data, escape) {
          return '<div class="no-results">No results found</div>'
        }
      }
    })
  }
}

// Chart colors matching bakery theme
const chartColors = {
  primary: '#8a3b2f',
  primarySoft: '#fbe4db',
  revenue: '#059669',
  expense: '#dc2626',
  neutral: '#8b6f5b',
  background: '#fff7f2',
  netPositive: '#059669',
  netNegative: '#dc2626'
}

// Formats a value based on chart format options.
// - format: 'currency' (pesos, divides by 100 if in cents), 'currency_pesos' (already in pesos), 'number' (default)
// - decimals: optional decimal places for number format
function formatChartValue(value, format, decimals) {
  if (value == null) return ''
  if (format === 'currency') {
    return (value / 100).toLocaleString('es-MX', { style: 'currency', currency: 'MXN', maximumFractionDigits: 0 })
  }
  if (format === 'currency_pesos') {
    return value.toLocaleString('es-MX', { style: 'currency', currency: 'MXN', maximumFractionDigits: 0 })
  }
  if (typeof decimals === 'number') {
    return value.toLocaleString('es-MX', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })
  }
  return value.toLocaleString('es-MX')
}

// Plugin: draw the value on top of each bar
const barValueLabelPlugin = {
  id: 'barValueLabel',
  afterDatasetsDraw(chart, args, opts) {
    const { ctx } = chart
    const format = opts?.format || 'number'
    const decimals = opts?.decimals
    ctx.save()
    ctx.font = '600 11px system-ui, -apple-system, sans-serif'
    ctx.fillStyle = '#141414'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'bottom'

    chart.data.datasets.forEach((dataset, datasetIndex) => {
      const meta = chart.getDatasetMeta(datasetIndex)
      if (!meta || meta.hidden) return
      meta.data.forEach((bar, i) => {
        const value = dataset.data[i]
        if (value == null || value === 0) return
        const formatted = formatChartValue(value, format, decimals)
        // For horizontal bars (indexAxis: 'y'), position to the right of the bar
        if (chart.options.indexAxis === 'y') {
          ctx.textAlign = 'left'
          ctx.textBaseline = 'middle'
          ctx.fillText(formatted, bar.x + 6, bar.y)
        } else {
          ctx.textAlign = 'center'
          ctx.textBaseline = 'bottom'
          ctx.fillText(formatted, bar.x, bar.y - 4)
        }
      })
    })
    ctx.restore()
  }
}

const BarChart = {
  mounted() {
    this.initChart()
  },

  updated() {
    if (this.chart) {
      this.chart.destroy()
    }
    this.initChart()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  },

  initChart() {
    const canvas = this.el.querySelector('canvas')
    if (!canvas) return

    const dataAttr = canvas.dataset.chartData
    if (!dataAttr) return

    let data
    try {
      data = JSON.parse(dataAttr)
    } catch (e) {
      console.error('Invalid chart data:', e)
      return
    }

    const ctx = canvas.getContext('2d')
    const format = data.format || 'number'
    const decimals = data.decimals

    this.chart = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: data.labels || [],
        datasets: data.datasets || []
      },
      plugins: [barValueLabelPlugin],
      options: {
        indexAxis: data.indexAxis || 'x',
        responsive: true,
        maintainAspectRatio: false,
        layout: {
          padding: { top: 24, right: data.indexAxis === 'y' ? 70 : 10 }
        },
        plugins: {
          barValueLabel: { format, decimals },
          legend: {
            display: (data.datasets || []).length > 1,
            position: 'top',
            labels: {
              usePointStyle: true,
              padding: 20,
              font: {
                family: 'system-ui, -apple-system, sans-serif',
                size: 12
              }
            }
          },
          tooltip: {
            backgroundColor: '#141414',
            titleFont: { family: 'system-ui', size: 13 },
            bodyFont: { family: 'system-ui', size: 12 },
            padding: 12,
            cornerRadius: 8,
            callbacks: {
              label: function(context) {
                const formatted = formatChartValue(context.raw, format, decimals)
                const label = context.dataset.label ? context.dataset.label + ': ' : ''
                return label + formatted
              }
            }
          }
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: {
              font: { family: 'system-ui', size: 11 },
              callback: function(value) {
                if (data.indexAxis === 'y') {
                  return formatChartValue(value, format, decimals)
                }
                return this.getLabelForValue(value)
              }
            }
          },
          y: {
            beginAtZero: true,
            grid: { color: 'rgba(100, 116, 139, 0.1)' },
            ticks: {
              font: { family: 'system-ui', size: 11 },
              callback: function(value) {
                if (data.indexAxis === 'y') {
                  return this.getLabelForValue(value)
                }
                return formatChartValue(value, format, decimals)
              }
            }
          }
        }
      }
    })
  }
}

const DoughnutChart = {
  mounted() {
    this.initChart()
  },

  updated() {
    if (this.chart) {
      this.chart.destroy()
    }
    this.initChart()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  },

  initChart() {
    const canvas = this.el.querySelector('canvas')
    if (!canvas) return

    const dataAttr = canvas.dataset.chartData
    if (!dataAttr) return

    let data
    try {
      data = JSON.parse(dataAttr)
    } catch (e) {
      console.error('Invalid chart data:', e)
      return
    }

    const ctx = canvas.getContext('2d')

    const format = data.format || 'number'
    const decimals = data.decimals

    // Draw value labels on each slice
    const doughnutValueLabelPlugin = {
      id: 'doughnutValueLabel',
      afterDatasetsDraw(chart) {
        const { ctx } = chart
        ctx.save()
        ctx.font = '600 11px system-ui, -apple-system, sans-serif'
        ctx.fillStyle = '#ffffff'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'

        chart.data.datasets.forEach((dataset, datasetIndex) => {
          const meta = chart.getDatasetMeta(datasetIndex)
          if (!meta || meta.hidden) return
          meta.data.forEach((arc, i) => {
            const value = dataset.data[i]
            if (value == null || value === 0) return
            // Only draw label if slice is big enough
            const angle = arc.endAngle - arc.startAngle
            if (angle < 0.25) return
            const pos = arc.tooltipPosition()
            const formatted = formatChartValue(value, format, decimals)
            ctx.fillText(formatted, pos.x, pos.y)
          })
        })
        ctx.restore()
      }
    }

    this.chart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: data.labels || [],
        datasets: data.datasets || []
      },
      plugins: [doughnutValueLabelPlugin],
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'right',
            labels: {
              usePointStyle: true,
              padding: 15,
              font: {
                family: 'system-ui, -apple-system, sans-serif',
                size: 12
              }
            }
          },
          tooltip: {
            backgroundColor: '#141414',
            titleFont: { family: 'system-ui', size: 13 },
            bodyFont: { family: 'system-ui', size: 12 },
            padding: 12,
            cornerRadius: 8,
            callbacks: {
              label: function(context) {
                const formatted = formatChartValue(context.raw, format, decimals)
                return context.label + ': ' + formatted
              }
            }
          }
        }
      }
    })
  }
}

const colocatedHooks = {
  SearchableSelect,
  BarChart,
  DoughnutChart
}

// Heroicons
// import "../vendor/heroicons"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// ==============================
// Add-to-Cart Button Animation
// ==============================

function initCartAnimations() {
  document.querySelectorAll('form[action*="/cart/add"]').forEach(form => {
    form.addEventListener('submit', e => {
      e.preventDefault()

      const btn = form.querySelector('button[type="submit"]')
      if (!btn || btn.classList.contains('cart-adding')) return

      // Animate button
      btn.classList.add('cart-adding')

      // Create bubble positioned relative to viewport (avoids overflow:hidden clip)
      const rect = btn.getBoundingClientRect()
      const bubble = document.createElement('div')
      bubble.className = 'cart-added-bubble'
      bubble.textContent = '¡Agregado! ✓'
      bubble.style.left = (rect.left + rect.width / 2) + 'px'
      bubble.style.top  = rect.top + 'px'
      document.body.appendChild(bubble)

      // Trigger CSS transition on next frame
      requestAnimationFrame(() => bubble.classList.add('visible'))

      // Use fetch so the page doesn't scroll to the top on reload
      fetch(form.action, {
        method: 'POST',
        body: new FormData(form),
        redirect: 'manual'  // silently follow the redirect, stay on page
      }).then(() => {
        // Update cart badge count in the header without a page reload
        const cartLink = document.querySelector('.storefront-cart-link')
        if (cartLink) {
          let badge = cartLink.querySelector('.storefront-cart-badge')
          if (badge) {
            badge.textContent = parseInt(badge.textContent, 10) + 1
          } else {
            badge = document.createElement('span')
            badge.className = 'storefront-cart-badge'
            badge.textContent = '1'
            cartLink.appendChild(badge)
          }
        }
      }).catch(() => {
        // Network error fallback — submit normally
        form.submit()
      }).finally(() => {
        setTimeout(() => {
          document.body.removeChild(bubble)
          btn.classList.remove('cart-adding')
        }, 580)
      })
    })
  })
}

document.addEventListener('DOMContentLoaded', initCartAnimations)

// ==============================
// Cart Quantity +/− Controls
// ==============================

function initQtyControls() {
  document.querySelectorAll('.qty-dec, .qty-inc').forEach(btn => {
    btn.addEventListener('click', function() {
      const variantId = this.dataset.variantId
      const input = document.getElementById('qty-' + variantId)
      const display = document.getElementById('qty-display-' + variantId)
      if (!input) return
      const delta = this.classList.contains('qty-dec') ? -1 : 1
      const newVal = Math.max(0, parseInt(input.value, 10) + delta)
      input.value = newVal
      if (display) display.textContent = newVal
      input.closest('form').submit()
    })
  })
}

document.addEventListener('DOMContentLoaded', initQtyControls)

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Handle hash-based scrolling after page load
const scrollToHash = () => {
  if (window.location.hash) {
    const element = document.querySelector(window.location.hash)
    if (element) {
      setTimeout(() => {
        element.scrollIntoView({ behavior: "smooth", block: "start" })
      }, 100)
    }
  }
}

// Handle scrolling for regular page loads
window.addEventListener("load", scrollToHash)

// Handle scrolling for LiveView navigation
window.addEventListener("phx:page-loading-stop", scrollToHash)

// Dropdown menu toggle functionality
window.toggleDropdown = function(button) {
  const dropdown = button.closest('.nav-dropdown')
  const menu = dropdown.querySelector('.nav-dropdown-menu')
  const icon = button.querySelector('.dropdown-icon')
  
  dropdown.classList.toggle('is-open')
  
  if (dropdown.classList.contains('is-open')) {
    menu.style.maxHeight = menu.scrollHeight + 'px'
    icon.style.transform = 'rotate(180deg)'
  } else {
    menu.style.maxHeight = '0'
    icon.style.transform = 'rotate(0deg)'
  }
}

// ==============================
// Casa Tame: Same-Currency Transfer Filter
// ==============================

const initTransferCurrencyFilter = () => {
  // Only active for Casa Tame domain
  if (document.body.dataset.domain !== 'casa-tame') return

  const fromSelect = document.getElementById('transfer_from_account_id')
  const toSelect   = document.getElementById('transfer_to_account_id')
  if (!fromSelect || !toSelect) return

  const lockMsg = document.getElementById('ct-currency-lock-msg')

  const filterToOptions = () => {
    const selectedOpt = fromSelect.options[fromSelect.selectedIndex]
    const fromCurrency = selectedOpt ? selectedOpt.dataset.currency : null

    Array.from(toSelect.options).forEach(opt => {
      if (!opt.value) return // skip the blank prompt option
      const optCurrency = opt.dataset.currency
      opt.disabled = !!(fromCurrency && optCurrency && optCurrency !== fromCurrency)
      opt.style.color = opt.disabled ? 'transparent' : ''
    })

    // If the currently-selected "to" account is now disabled, clear it
    const currentTo = toSelect.options[toSelect.selectedIndex]
    if (currentTo && currentTo.disabled) toSelect.value = ''

    // Update the lock hint below the "to" select
    if (lockMsg) {
      if (fromCurrency) {
        lockMsg.textContent = `🔒 Locked to ${fromCurrency} accounts`
        lockMsg.style.display = ''
      } else {
        lockMsg.style.display = 'none'
      }
    }
  }

  fromSelect.addEventListener('change', filterToOptions)
  // Run immediately for edit form (pre-selected value)
  filterToOptions()
}

document.addEventListener('DOMContentLoaded', initTransferCurrencyFilter)
window.addEventListener('phx:page-loading-stop', initTransferCurrencyFilter)

// Close action dropdowns (<details>) when clicking outside
document.addEventListener("click", function(e) {
  document.querySelectorAll("details.action-dropdown[open]").forEach(function(el) {
    if (!el.contains(e.target)) el.removeAttribute("open")
  })
})

// Initialize dropdowns without animation
const initializeDropdowns = () => {
  const dropdowns = document.querySelectorAll('.nav-dropdown')
  dropdowns.forEach(dropdown => {
    const menu = dropdown.querySelector('.nav-dropdown-menu')
    const icon = dropdown.querySelector('.dropdown-icon')
    
    // Disable transitions during initialization
    menu.classList.add('no-transition')
    if (icon) {
      icon.style.transition = 'none'
    }
    
    // Open only dropdowns with data-default-open="true"
    const shouldBeOpen = dropdown.getAttribute('data-default-open') === 'true'
    if (shouldBeOpen) {
      dropdown.classList.add('is-open')
      menu.style.maxHeight = menu.scrollHeight + 'px'
      if (icon) {
        icon.style.transform = 'rotate(180deg)'
      }
    } else {
      dropdown.classList.remove('is-open')
      menu.style.maxHeight = '0'
      if (icon) {
        icon.style.transform = 'rotate(0deg)'
      }
    }
    
    // Re-enable transitions after styles are set
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        menu.classList.remove('no-transition')
        if (icon) {
          icon.style.transition = ''
        }
      })
    })
  })
}

// Initialize dropdowns as early as possible (DOMContentLoaded fires before images load,
// preventing the visible "collapsed then expanded" flash on page load).
document.addEventListener('DOMContentLoaded', initializeDropdowns)

// Re-initialize dropdowns after LiveView navigation (without animation)
window.addEventListener('phx:page-loading-stop', initializeDropdowns)

// ==============================
// Mobile Hamburger Menu
// ==============================

const initHamburgerMenu = () => {
  const hamburgerBtn = document.getElementById('hamburger-btn')
  const sidebar = document.getElementById('sidebar')
  const overlay = document.getElementById('sidebar-overlay')

  if (!hamburgerBtn || !sidebar || !overlay) return

  const toggleMenu = (open) => {
    const isOpen = open !== undefined ? open : !sidebar.classList.contains('is-open')
    sidebar.classList.toggle('is-open', isOpen)
    overlay.classList.toggle('is-open', isOpen)
    hamburgerBtn.setAttribute('aria-expanded', isOpen)

    // Prevent body scroll when menu is open
    document.body.style.overflow = isOpen ? 'hidden' : ''
  }

  // Toggle on hamburger click
  hamburgerBtn.addEventListener('click', (e) => {
    e.stopPropagation()
    toggleMenu()
  })

  // Close on overlay click
  overlay.addEventListener('click', () => toggleMenu(false))

  // Close menu when a nav link is clicked
  sidebar.querySelectorAll('.nav-link').forEach(link => {
    link.addEventListener('click', () => toggleMenu(false))
  })

  // Close on escape key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && sidebar.classList.contains('is-open')) {
      toggleMenu(false)
    }
  })
}

// Initialize hamburger menu as early as possible
document.addEventListener('DOMContentLoaded', initHamburgerMenu)

// Re-initialize after LiveView navigation
window.addEventListener('phx:page-loading-stop', initHamburgerMenu)

// ==============================
// Calendar detail panel + tooltip
// ==============================

const statusLabels = {
  new_order: 'New',
  in_prep: 'In Prep',
  ready: 'Ready',
  delivered: 'Delivered',
  canceled: 'Canceled',
  scheduled: 'Scheduled',
  completed: 'Completed',
  cancelled: 'Cancelled'
}

const statusColors = {
  new_order: '#3b82f6',
  in_prep: '#f59e0b',
  ready: '#10b981',
  delivered: '#6b7280',
  canceled: '#ef4444',
  scheduled: '#3b82f6',
  completed: '#10b981',
  cancelled: '#ef4444'
}

function escapeHtml(str) {
  if (str == null) return ''
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

const initCalendarDetailPanel = () => {
  const panel = document.getElementById('calendar-detail-panel')
  if (!panel) return

  const backdrop = panel.querySelector('.calendar-detail-backdrop')
  const titleEl = document.getElementById('calendar-detail-title')
  const ordersEl = document.getElementById('calendar-detail-orders')
  const closeBtn = document.getElementById('calendar-detail-close')

  const openPanel = (dayEl) => {
    const label = dayEl.dataset.dayLabel
    const ordersJson = dayEl.dataset.orders
    if (!ordersJson) return

    let orders
    try {
      orders = JSON.parse(ordersJson)
    } catch (e) {
      return
    }

    if (!orders || orders.length === 0) return

    titleEl.textContent = label
    ordersEl.innerHTML = orders.map(o => {
      const product = o.product || '—'
      const qty = o.quantity > 1 ? ` ×${o.quantity}` : ''
      const time = o.delivery_time ? ` · ${escapeHtml(o.delivery_time)}` : ''
      const status = statusLabels[o.status] || o.status
      const color = statusColors[o.status] || '#6b7280'

      return `
        <a href="${escapeHtml(o.url)}" class="cdp-order-item">
          <span class="cdp-order-dot" style="background:${color};"></span>
          <div class="cdp-order-info">
            <span class="cdp-order-name">${escapeHtml(o.customer_name)}</span>
            <span class="cdp-order-meta">${escapeHtml(product)}${escapeHtml(qty)} · ${escapeHtml(status)}${time}</span>
          </div>
        </a>
      `
    }).join('')

    panel.classList.add('is-open')
    panel.setAttribute('aria-hidden', 'false')
    document.body.style.overflow = 'hidden'
  }

  const closePanel = () => {
    panel.classList.remove('is-open')
    panel.setAttribute('aria-hidden', 'true')
    document.body.style.overflow = ''
  }

  // Count badge click: opens panel on all devices
  document.querySelectorAll('.calendar-orders-count').forEach(countEl => {
    countEl.addEventListener('click', (e) => {
      const dayEl = e.currentTarget.closest('.calendar-day')
      if (dayEl) openPanel(dayEl)
    })
  })

  // "+N more" button click: opens panel (desktop)
  document.querySelectorAll('.calendar-order-more').forEach(moreBtn => {
    moreBtn.addEventListener('click', (e) => {
      const dayEl = e.currentTarget.closest('.calendar-day')
      if (dayEl) openPanel(dayEl)
    })
  })

  if (backdrop) backdrop.addEventListener('click', closePanel)
  if (closeBtn) closeBtn.addEventListener('click', closePanel)

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && panel.classList.contains('is-open')) {
      closePanel()
    }
  })
}

const initCalendarTooltip = () => {
  const tooltip = document.getElementById('calendar-tooltip')
  if (!tooltip) return

  document.querySelectorAll('.calendar-order-item[data-tooltip-content]').forEach(item => {
    item.addEventListener('mouseenter', (e) => {
      const content = e.currentTarget.dataset.tooltipContent
      if (!content) return
      tooltip.textContent = content
      tooltip.classList.add('is-visible')
    })

    item.addEventListener('mousemove', (e) => {
      const x = e.clientX + 14
      const y = e.clientY - 8
      const tw = tooltip.offsetWidth
      const th = tooltip.offsetHeight
      tooltip.style.left = Math.min(x, window.innerWidth - tw - 12) + 'px'
      tooltip.style.top = Math.max(8, Math.min(y, window.innerHeight - th - 12)) + 'px'
    })

    item.addEventListener('mouseleave', () => {
      tooltip.classList.remove('is-visible')
    })
  })
}

const initCalendar = () => {
  initCalendarDetailPanel()
  initCalendarTooltip()
}

window.addEventListener('load', initCalendar)
window.addEventListener('phx:page-loading-stop', initCalendar)

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

