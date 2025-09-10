export const ConfigDisplay = {
    props: {
        config: {
            type: Object,
            required: true
        }
    },
    
    setup() {
        const { ref } = Vue;
        
        const activeTab = ref('inbounds');
        
        const tabs = [
            { key: 'inbounds', name: '入站', icon: '📥' },
            { key: 'outbounds', name: '出站', icon: '📤' },
            { key: 'route', name: '路由', icon: '🛣️' },
            { key: 'dns', name: 'DNS', icon: '🌐' }
        ];
        
        return {
            activeTab,
            tabs
        };
    },
    
    template: `
        <div class="config-section">
            <div class="config-tabs">
                <button 
                    v-for="tab in tabs" 
                    :key="tab.key"
                    @click="activeTab = tab.key"
                    :class="{ active: activeTab === tab.key }"
                    class="config-tab"
                >
                    <span class="tab-icon">{{ tab.icon }}</span>
                    <span class="tab-text">{{ tab.name }}</span>
                </button>
            </div>
            
            <div class="config-content">
                <!-- 入站配置 -->
                <div v-if="activeTab === 'inbounds'" class="config-panel">
                    <div class="panel-header">
                        <h3>📥 入站配置</h3>
                        <span class="item-count">{{ config.inbounds?.length || 0 }} 个入站</span>
                    </div>
                    <div v-if="config.inbounds?.length" class="config-items">
                        <div v-for="(inbound, index) in config.inbounds" :key="index" class="config-item">
                            <div class="item-header">
                                <span class="item-type">{{ inbound.type }}</span>
                                <span class="item-tag">{{ inbound.tag || `入站${index + 1}` }}</span>
                            </div>
                            <div class="item-details">
                                <div class="detail-row">
                                    <span class="label">监听地址:</span>
                                    <span class="value">{{ inbound.listen || '0.0.0.0' }}:{{ inbound.listen_port || 'N/A' }}</span>
                                </div>
                                <div v-if="inbound.users?.length" class="detail-row">
                                    <span class="label">用户数:</span>
                                    <span class="value">{{ inbound.users.length }} 个</span>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div v-else class="no-config">
                        没有配置入站规则
                    </div>
                </div>
                
                <!-- 出站配置 -->
                <div v-if="activeTab === 'outbounds'" class="config-panel">
                    <div class="panel-header">
                        <h3>📤 出站配置</h3>
                        <span class="item-count">{{ config.outbounds?.length || 0 }} 个出站</span>
                    </div>
                    <div v-if="config.outbounds?.length" class="config-items">
                        <div v-for="(outbound, index) in config.outbounds" :key="index" class="config-item">
                            <div class="item-header">
                                <span class="item-type">{{ outbound.type }}</span>
                                <span class="item-tag">{{ outbound.tag || `出站${index + 1}` }}</span>
                            </div>
                            <div class="item-details">
                                <div v-if="outbound.server" class="detail-row">
                                    <span class="label">服务器:</span>
                                    <span class="value">{{ outbound.server }}:{{ outbound.server_port || 'N/A' }}</span>
                                </div>
                                <div v-if="outbound.method" class="detail-row">
                                    <span class="label">方法:</span>
                                    <span class="value">{{ outbound.method }}</span>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div v-else class="no-config">
                        没有配置出站规则
                    </div>
                </div>
                
                <!-- 路由配置 -->
                <div v-if="activeTab === 'route'" class="config-panel">
                    <div class="panel-header">
                        <h3>🛣️ 路由配置</h3>
                        <span class="item-count">{{ config.route?.rules?.length || 0 }} 个规则</span>
                    </div>
                    <div v-if="config.route?.rules?.length" class="config-items">
                        <div v-for="(rule, index) in config.route.rules" :key="index" class="config-item">
                            <div class="item-header">
                                <span class="item-type">规则 {{ index + 1 }}</span>
                                <span class="item-tag">{{ rule.outbound || 'default' }}</span>
                            </div>
                            <div class="item-details">
                                <div v-if="rule.domain" class="detail-row">
                                    <span class="label">域名:</span>
                                    <span class="value">{{ rule.domain.length }} 个规则</span>
                                </div>
                                <div v-if="rule.ip" class="detail-row">
                                    <span class="label">IP:</span>
                                    <span class="value">{{ rule.ip.length }} 个规则</span>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div v-else class="no-config">
                        没有配置路由规则
                    </div>
                </div>
                
                <!-- DNS配置 -->
                <div v-if="activeTab === 'dns'" class="config-panel">
                    <div class="panel-header">
                        <h3>🌐 DNS 配置</h3>
                    </div>
                    <div v-if="config.dns" class="config-items">
                        <div class="config-item">
                            <div class="item-header">
                                <span class="item-type">DNS 服务器</span>
                            </div>
                            <div class="item-details">
                                <div v-if="config.dns.servers" class="detail-row">
                                    <span class="label">服务器:</span>
                                    <span class="value">{{ config.dns.servers.length }} 个</span>
                                </div>
                                <div v-if="config.dns.final" class="detail-row">
                                    <span class="label">默认服务器:</span>
                                    <span class="value">{{ config.dns.final }}</span>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div v-else class="no-config">
                        没有配置DNS设置
                    </div>
                </div>
            </div>
        </div>
    `
};
