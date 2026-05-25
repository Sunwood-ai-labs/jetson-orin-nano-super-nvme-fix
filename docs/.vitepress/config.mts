import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Jetson NVMe Boot Fix',
  description: 'NVMe boot repair and local LLM experiment notes for Jetson Orin Nano Super 8GB',
  base: '/jetson-orin-nano-super-nvme-fix/',
  cleanUrls: true,
  themeConfig: {
    logo: '/jetson-nvme-llm.svg',
    nav: [
      { text: 'Guide', link: '/guide/' },
      { text: 'LLM', link: '/guide/local-llm' },
      { text: '日本語', link: '/ja/' },
      { text: 'GitHub', link: 'https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix' }
    ],
    sidebar: {
      '/guide/': [
        {
          text: 'Guide',
          items: [
            { text: 'Overview', link: '/guide/' },
            { text: 'NVMe Boot Repair', link: '/guide/nvme-boot-repair' },
            { text: 'Local LLM Experiment', link: '/guide/local-llm' },
            { text: 'Safety Notes', link: '/guide/safety' }
          ]
        }
      ],
      '/ja/': [
        {
          text: '日本語',
          items: [
            { text: '概要', link: '/ja/' },
            { text: '記事', link: '/ja/article' }
          ]
        }
      ]
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix' }
    ]
  }
})
