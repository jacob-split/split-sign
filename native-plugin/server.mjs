import {pathToFileURL} from 'node:url';
const root=process.env.SPLIT_WEBSITE_PLUGIN_ROOT||'/home/jacob/Split/src/split-payments-website/native-plugins';
process.env.SPLIT_SIGNATURE_PLUGIN_ROOT=new URL('.',import.meta.url).pathname;
const {launch}=await import(pathToFileURL(root+'/server.mjs').href);
await launch('signature',{htmlPath:new URL('./dist/signature.html',import.meta.url)});
