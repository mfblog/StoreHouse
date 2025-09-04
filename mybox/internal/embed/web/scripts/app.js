import { ServiceCard } from '../components/ServiceCard.js';
import { ConfigDisplay } from '../components/ConfigDisplay.js';

const API_BASE = '';

export const createApp = () => {
    const { createApp, ref, reactive, onMounted, watch } = Vue;
    
    return createApp({
        components: {
            ServiceCard,
            ConfigDisplay
        },
        
        setup() {
            // 状态
            const services = reactive({
                'sing-box': {},
                'mosdns': {}
            });
            
            const loading = reactive({
                'sing-box': false,
                'mosdns': false
            });
            
            const error = reactive({
                'sing-box': null,
                'mosdns': null
            });
            
            const currentPage = ref('home');
            const sidebarVisible = ref(true);
            const collapsedGroups = reactive({
                proxy: false,
                dns: false
            });
            
            // Sing-Box配置状态
            const singboxConfig = ref(null);
            const loadingConfig = ref(false);
            const configError = ref(null);
            
            // 从localStorage恢复状态
            onMounted(() => {
                const savedSidebarState = localStorage.getItem('sidebarVisible');
                if (savedSidebarState !== null) {
                    sidebarVisible.value = JSON.parse(savedSidebarState);
                }
                
                const savedCollapsedGroups = localStorage.getItem('collapsedGroups');
                if (savedCollapsedGroups) {
                    Object.assign(collapsedGroups, JSON.parse(savedCollapsedGroups));
                }
                
                // 初始化数据
                fetchServicesStatus();
            });
            
            // 监听状态变化并保存
            watch(sidebarVisible, (newValue) => {
                localStorage.setItem('sidebarVisible', JSON.stringify(newValue));
            });
            
            watch(collapsedGroups, (newValue) => {
                localStorage.setItem('collapsedGroups', JSON.stringify(newValue));
            }, { deep: true });
            
            // 方法
            const toggleSidebar = () => {
                sidebarVisible.value = !sidebarVisible.value;
            };
            
            const toggleGroup = (groupName) => {
                collapsedGroups[groupName] = !collapsedGroups[groupName];
            };
            
            const showServicePage = (serviceName) => {
                currentPage.value = serviceName;
                fetchServicesStatus();
                
                if (serviceName === 'sing-box') {
                    fetchSingBoxConfig();
                }
            };
            
            const showHomePage = () => {
                currentPage.value = 'home';
            };
            
            // API调用
            const fetchServicesStatus = async () => {
                for (const serviceName of Object.keys(services)) {
                    loading[serviceName] = true;
                    error[serviceName] = null;
                    
                    try {
                        const response = await fetch(`${API_BASE}/services`);
                        const data = await response.json();
                        
                        if (response.ok) {
                            Object.assign(services[serviceName], data.services[serviceName] || {});
                        } else {
                            error[serviceName] = data.error || '获取服务状态失败';
                        }
                    } catch (err) {
                        error[serviceName] = `获取服务状态失败: ${err.message}`;
                    } finally {
                        loading[serviceName] = false;
                    }
                }
            };
            
            const fetchSingBoxConfig = async () => {
                loadingConfig.value = true;
                configError.value = null;
                
                try {
                    const response = await fetch(`${API_BASE}/config/sing-box`);
                    const data = await response.json();
                    
                    if (response.ok) {
                        singboxConfig.value = data.config;
                    } else {
                        configError.value = data.error || '获取配置失败';
                    }
                } catch (error) {
                    configError.value = `获取配置失败: ${error.message}`;
                } finally {
                    loadingConfig.value = false;
                }
            };
            
            const handleServiceAction = async ({ service, action }) => {
                if (action === 'logs') {
                    try {
                        const response = await fetch(`${API_BASE}/logs/${service}?lines=50`);
                        const data = await response.json();
                        
                        if (response.ok) {
                            const logs = data.logs.join('\n');
                            const newWindow = window.open('', '_blank');
                            newWindow.document.write(`
                                <!DOCTYPE html>
                                <html>
                                <head>
                                    <title>${service} 日志</title>
                                    <style>
                                        body { 
                                            font-family: monospace; 
                                            padding: 20px;
                                            background: #f3f4f6;
                                        }
                                        pre {
                                            background: white;
                                            padding: 15px;
                                            border-radius: 8px;
                                            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                                            overflow-x: auto;
                                        }
                                    </style>
                                </head>
                                <body>
                                    <pre>${logs || '暂无日志'}</pre>
                                </body>
                                </html>
                            `);
                            newWindow.document.close();
                            return;
                        }
                        throw new Error(data.error || '获取日志失败');
                    } catch (error) {
                        alert(`获取日志失败: ${error.message}`);
                        return;
                    }
                }
                
                if (!['start', 'stop', 'restart'].includes(action)) return;
                
                try {
                    const response = await fetch(`${API_BASE}/services/${service}/${action}`, {
                        method: 'POST'
                    });
                    const data = await response.json();
                    
                    if (!response.ok) {
                        throw new Error(data.error || `${action}失败`);
                    }
                    
                    // 等待一会再刷新状态
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    await fetchServicesStatus();
                } catch (error) {
                    alert(`操作失败: ${error.message}`);
                }
            };
            
            return {
                services,
                loading,
                error,
                currentPage,
                sidebarVisible,
                collapsedGroups,
                singboxConfig,
                loadingConfig,
                configError,
                toggleSidebar,
                toggleGroup,
                showServicePage,
                showHomePage,
                handleServiceAction
            };
        }
    });
};
