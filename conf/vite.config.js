import { sveltekit } from '@sveltejs/kit/vite';
import path from 'path';
import { defineConfig } from 'vite'

/** @type {import('vite').UserConfig} */
const config = {
	resolve: {
		alias: {
			'xmlhttprequest-ssl': './node_modules/engine.io-client/lib/xmlhttprequest.js',
			'@api': path.resolve('./src/api')
		}
	},
	plugins: [sveltekit()],
	server: {
    	port: __PORT__,
  	},
};

export default defineConfig(config)