export const ServiceCard = {
    props: {
        service: {
            type: Object,
            required: true
        },
        serviceName: {
            type: String,
            required: true
        }
    },
    
    emits: ['action'],
    
    setup(props, { emit }) {
        const { ref, computed } = Vue;
        
        const actionInProgress = ref(false);
        
        // 计算属性
        const serviceIcon = computed(() => {
            switch (props.serviceName) {
                case 'sing-box': return '🚀';
                case 'mosdns': return '🌐';
                default: return '⚙️';
            }
        });
        
        const serviceDisplayName = computed(() => {
            switch (props.serviceName) {
                case 'sing-box': return 'Sing-Box';
                case 'mosdns': return 'MosDNS';
                default: return props.serviceName;
            }
        });
        
        const serviceDescription = computed(() => {
            switch (props.serviceName) {
                case 'sing-box': return '多协议代理平台';
                case 'mosdns': return 'DNS 转发器 • 智能分流';
                default: return '系统服务';
            }
        });
        
        const statusClass = computed(() => {
            switch (props.service.status) {
                case 0: return 'status-running';
                case 1: return 'status-stopped';
                default: return 'status-error';
            }
        });
        
        const statusText = computed(() => {
            switch (props.service.status) {
                case 0: return '运行中';
                case 1: return '已停止';
                default: return '未安装';
            }
        });
        
        const isRunning = computed(() => props.service.status === 0);
        
        const uptime = computed(() => {
            if (!isRunning.value || !props.service.start_time) return '';
            
            const startTime = new Date(props.service.start_time);
            const now = new Date();
            const diffMs = now - startTime;
            
            const days = Math.floor(diffMs / (1000 * 60 * 60 * 24));
            const hours = Math.floor((diffMs % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
            const minutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));
            
            if (days > 0) return `${days}天 ${hours}小时`;
            if (hours > 0) return `${hours}小时 ${minutes}分钟`;
            if (minutes > 0) return `${minutes}分钟`;
            return '少于1分钟';
        });
        
        // 方法
        const handleAction = async (action) => {
            if (actionInProgress.value) return;
            
            actionInProgress.value = true;
            try {
                await emit('action', { service: props.serviceName, action });
            } finally {
                actionInProgress.value = false;
            }
        };
        
        return {
            actionInProgress,
            serviceIcon,
            serviceDisplayName,
            serviceDescription,
            statusClass,
            statusText,
            isRunning,
            uptime,
            handleAction
        };
    },
    
    template: `
        <div class="service-card card">
            <div class="card-header">
                <div class="service-info">
                    <h3 class="card-title">
                        <span class="service-icon">{{ serviceIcon }}</span>
                        {{ serviceDisplayName }}
                    </h3>
                    <p class="service-description">{{ serviceDescription }}</p>
                </div>
                <div class="service-status">
                    <span class="status-badge" :class="statusClass">
                        {{ statusText }}
                    </span>
                </div>
            </div>
            
            <div v-if="isRunning" class="service-uptime">
                <span class="uptime-label">运行时长:</span>
                <span class="uptime-value">{{ uptime }}</span>
            </div>
            
            <div class="service-actions">
                <template v-if="service.status !== 2">
                    <button 
                        v-if="isRunning"
                        class="btn btn-danger"
                        :disabled="actionInProgress"
                        @click="handleAction('stop')"
                    >
                        停止
                    </button>
                    <button 
                        v-if="isRunning"
                        class="btn btn-primary"
                        :disabled="actionInProgress"
                        @click="handleAction('restart')"
                    >
                        重启
                    </button>
                    <button 
                        v-if="!isRunning"
                        class="btn btn-primary"
                        :disabled="actionInProgress"
                        @click="handleAction('start')"
                    >
                        启动
                    </button>
                    <button 
                        class="btn btn-secondary"
                        :disabled="actionInProgress"
                        @click="handleAction('logs')"
                    >
                        查看日志
                    </button>
                </template>
                <div v-else>
                    服务未安装
                </div>
            </div>
        </div>
    `
};
