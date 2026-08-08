%===============���Ϻ����ױ��ͼ��===============%
clc;
clear all;
close all;
%% ��1.��γ�Ⱥ�ͼƬ�ݺ�����á�
Lon_lim = [113.5,122]; %�������ȷ�Χ
Lat_lim = [18,23.5];   %����γ�ȷ�Χ
k = ((Lat_lim(2)-Lat_lim(1))*111)/((Lon_lim(2)-Lon_lim(1))*111*cosd((Lat_lim(1)+Lat_lim(2))/2)); %��γ��ת�ɾ������ʵ���ݺ��
figure(1);
set(gcf,'color','w');
set(gcf,'Position',[50,50,1050,500]);
hn1 = axes('Position',[0.05,0.15,0.6,0.8]);
%% ��2.etopo1ˮ�����ݡ�
[dep,~] = etopo('D:\Software\Matlab2021\toolbox\toolbox_RLT\ETOPO1\etopo1_bed_c_f4.flt',1,Lat_lim,Lon_lim); %ETOPO1ˮ������
[Lon,Lat] = meshgrid(linspace(Lon_lim(1),Lon_lim(2),size(dep,2)),linspace(Lat_lim(1),Lat_lim(2),size(dep,1))); %��������
dep_index = find(dep(:)>0);
dep(dep_index) = 50;
%% ��3.��ͼ��
m_proj('mercator','lon',Lon_lim,'lat',Lat_lim); %ͶӰ��ʽ�;�γ�ȷ�Χ
min_dep_500 = 500*floor((min(min(dep)))/500); %�����Сֵ��500��������������
max_dep_500 = 50;  %������ֵ��500��������������
m_contourf(Lon,Lat,dep,min_dep_500:25:max_dep_500,'linestyle','none'); %�����ɫ�ĵ�ֵ��(ÿ25mһ��������)
hold on;
[c2,h2] = m_contour(Lon,Lat,dep,[0,-50,-200,-500],'linewidth',0.35,'color','k'); %����ˮ���ֵ��
clabel(c2,h2,'manual','fontsize',8,'fontname','Times New Roman');
% m_grid('linestyle',':','box','on','tickdir','in','linecolor','w','alpha','0.5','fontname','Times New Roman','fontweight','bold','fontsize',16); %��������ͱ߿�
m_grid('linestyle',':','box','fancy','tickdir','in','linecolor','w','alpha','0.5','fontname','Times New Roman','fontweight','bold','fontsize',16); %��������ͱ߿�

%% ��4.colormap��
hh = colorbar;
set(hh,'position',[0.64,0.15,0.03,0.8],'fontname','Times New Roman','fontsize',12,'ytick',[-4000:1000:10],'yticklabel',[4000,3000,2000,1000,0]);
set(get(hh,'title'),'string','\fontname{Times new roman}Depth (m)','fontsize',14); %��ɫ����ӵ�λ
caxis([min_dep_500,max_dep_500]);
colormap([m_colmap('water',abs(min_dep_500));flipud(m_colmap('gland',abs(max_dep_500)))]);
%% ��5.�������ֱ�ע��
m_text(120.3,23.4,'Taiwan','Color','k','FontSize',16,'vertical','top','FontWeight','bold');

m_text(114.1,23.4,'China','Color','k','FontSize',16,'vertical','top','FontWeight','bold');
m_text(120.7,18.5,'Luzon','Color','k','FontSize',16,'vertical','top','FontWeight','bold');
m_text(mean(Lon_lim),19.5,'South China Sea','Color','k','FontSize',20,'vertical','top','horizontal','center','FontWeight','bold');

%% ��6.Ǳ��ͼ�꡿
m_plot(116.85,20.71,'kp','Linewidth',3,'color','r');
m_text(117.6,20.8,'Dongsha','Color','k','FontSize',12,'vertical','middle','horizontal','center','FontWeight','bold');
m_text(117.6,20.5,'Atoll','Color','k','FontSize',12,'vertical','middle','horizontal','center','FontWeight','bold');
sta_A = m_line(115.77536,20.82578,'marker','o','color','k','linewidth',1,'linestyle','none','markersize',10,'markerfacecolor','y');
m_text(115.75,20.6,'Mooring','Color','k','FontSize',12,'vertical','middle','horizontal','center','FontWeight','bold');



%% ��7.����Bվ��Dվ��Eվ��ˮ�����桿
%=====��7.0.׼����������ʼ�㡿=====%
pos = [115.5716,20.3653;115.5501,20.6892;115.1530,20.4654]; %BDEվ����
DE_mid = 0.5*[pos(2,1)+pos(3,1),pos(2,2)+pos(3,2)]; %DE�����е������
s_point = [DE_mid(1)-0.5*(pos(1,1)-DE_mid(1)),DE_mid(2)+0.5*(DE_mid(2)-pos(1,2))]; %��ʼ��λ������
e_point = [pos(1,1)+0.5*(pos(1,1)-DE_mid(1)),pos(1,2)-0.5*(DE_mid(2)-pos(1,2))];   %��ֹ��λ������
L_se = m_lldist([s_point(1),e_point(1)],[s_point(2),e_point(2)]); %��ֹ��֮ǰ�ľ���(km)
L_sE = 0.75*L_se-m_lldist([pos(1,1),pos(3,1)],[pos(1,2),pos(3,2)]); %��ʼ�㵽E��ľ���
L_sD = 0.75*L_se-m_lldist([pos(1,1),pos(2,1)],[pos(1,2),pos(2,2)]); %��ʼ�㵽D��ľ���
% L_sB = 0.25*L_se; %��ʼ�㵽B��ľ���
L_sB = 45;
%=====��7.1.�������ˮ��������ݲ��������桿=====%
data_dx = load('D:\ѧϰ����\������ʦ����������\Ǳ��-����̩\Ǳ�껭ͼ\006-�ڰ˰�\RLT_program_and_figure\1_��һ����\Bվ\ADCP���ټ�����\�������ͼ\����\staBDE_profile_depth.xyz');
dep_dx = data_dx(:,3);
dep_dx = flip(dep_dx);
% figure(2);
% set(gcf,'position',[50,50,300,500]);
k_range = length(dep_dx)/L_se; %��ȵ����;���ı�
hn2 = axes('Position',[0.72,0.15,0.2,0.8]);

yy_tick = 700:-100:0;
area(dep_dx,100*floor((min(dep_dx))/100),'facecolor','k'); %��ɫ���׵���
set(gca,'xtick',[0,1000],'xticklabel',{'20��','21��N'},'YAxisLocation','right','fontname','Times New Roman','fontsize',14,'tickdir','out');
set(gca,'xlim',[0,1000],'ylim',[-700,0],'yticklabel',yy_tick,'fontname','Times New Roman','fontsize',14,'box','off');
% text(-0.32,0.4,'\fontname{����}���\fontname{Times new roman}/m','fontsize',14,'horizontalalignment','left','verticalalignment','top','Units','normalized','Rotation',90);
ylabel('\fontname{Times new roman}Depth (m)','fontsize',14);
text('string','{\fontname{times new roman}(b)}','Units','normalized','position',[0.5,-0.12],'fontname','times new roman','color','k','fontsize',18,'HorizontalAlignment','center','VerticalAlignment','middle');
text('string','{\fontname{times new roman}(a)}','Units','normalized','position',[-1.8,-0.12],'fontname','times new roman','color','k','fontsize',18,'HorizontalAlignment','center','VerticalAlignment','middle');
%=====��7.2.��¼BDE����վ���������İ�װ�����Ϣ��=====%
dep_T_staB         = -310:20:-30;
dep_CTD_staB       = -300:20:-20;
dep_ADCP_1M_staB = -315;
dep_ADCP_300k_staB = [-105,-205,-305];




% dep_T_staD         = [-130:10:-60,-138,-240:10:-160];
% dep_CTD_staD       = [-250:50:-50,-306];
% dep_ADCP_75k_staD  = -308;
% dep_Aaderaa_staD   = [-149,-313];
% 
% dep_T_staE         = [-90:10:-60,-130:10:-110,-138,-190:10:-160];
% dep_CTD_staE       = [-200:50:-50,-226];
% dep_ADCP_75k_staE  = -224;
% dep_Aaderaa_staE   = [-149,-228];
%=====��7.3.��Ǳ������=====%
%=====��Bվ��=====%
hold on;
plot([L_sB*k_range,L_sB*k_range],[100*floor((min(dep_dx))/100),0],'k-','linewidth',1.2); %BվǱ��ĺ�ɫ������
hold on;
f1 = plot(L_sB*k_range*ones(1,length(dep_T_staB)),dep_T_staB,'o','MarkerFaceColor','m','MarkerSize',7,'color','none');
hold on;
f2 = plot(L_sB*k_range*ones(1,length(dep_CTD_staB)),dep_CTD_staB,'s','MarkerFaceColor','b','MarkerSize',7,'color','none');
hold on;
f3 = plot(L_sB*k_range*ones(1,length(dep_ADCP_300k_staB)),dep_ADCP_300k_staB,'^','MarkerFaceColor','g','MarkerSize',7,'color','none');
hold on;
f4 = plot(L_sB*k_range*ones(1,length(dep_ADCP_1M_staB)),dep_ADCP_1M_staB,'v','MarkerFaceColor','r','MarkerSize',7,'color','none');
hold on;
plot([L_sB*k_range,L_sB*k_range],0,'o','MarkerFaceColor','y','MarkerSize',7,'color','k'); 
%=====��Dվ��=====%
% hold on;
% plot([27*k_range,27*k_range],[100*floor((min(dep_dx))/100),0],'k--','linewidth',1.2); %DվǱ��ĺ�ɫ������
% hold on;
% plot(27*k_range*ones(1,length(dep_T_staD)),dep_T_staD,'o','MarkerFaceColor','m','MarkerSize',7,'color','none');
% hold on;
% plot(27*k_range*ones(1,length(dep_CTD_staD)),dep_CTD_staD,'s','MarkerFaceColor','b','MarkerSize',7,'color','none');
% hold on;
% plot(27*k_range*ones(1,length(dep_Aaderaa_staD)),dep_Aaderaa_staD,'d','MarkerFaceColor',[0.625,0.125,0.9375],'MarkerSize',7,'color','none');
% hold on;
% plot(27*k_range*ones(1,length(dep_ADCP_75k_staD)),dep_ADCP_75k_staD,'^','MarkerFaceColor','r','MarkerSize',7,'color','none');
% %=====��Eվ��=====%
% hold on;
% plot([17*k_range,17*k_range],[100*floor((min(dep_dx))/100),0],'k--','linewidth',1.2); %EվǱ��ĺ�ɫ������
% hold on;
% plot(17*k_range*ones(1,length(dep_T_staE)),dep_T_staE,'o','MarkerFaceColor','m','MarkerSize',7,'color','none');
% hold on;
% plot(17*k_range*ones(1,length(dep_CTD_staE)),dep_CTD_staE,'s','MarkerFaceColor','b','MarkerSize',7,'color','none');
% hold on;
% plot(17*k_range*ones(1,length(dep_Aaderaa_staE)),dep_Aaderaa_staE,'d','MarkerFaceColor',[0.625,0.125,0.9375],'MarkerSize',7,'color','none');
% hold on;
% plot(17*k_range*ones(1,length(dep_ADCP_75k_staE)),dep_ADCP_75k_staE,'^','MarkerFaceColor','r','MarkerSize',7,'color','none');
% hold on;
% plot(17*k_range,0,'marker','o','color','k','linewidth',1,'linestyle','none','markersize',8,'markerfacecolor','yellow');
% plot(27*k_range,0,'marker','o','color','k','linewidth',1,'linestyle','none','markersize',8,'markerfacecolor','green');
% plot(L_sB*k_range,0,'marker','o','color','k','linewidth',1,'linestyle','none','markersize',8,'markerfacecolor','yellow');
legend([f1,f2,f3,f4],'T','CTD','300K ADCP','1M ADCP','location','Southeast','fontsize',10);
% print('-djpeg','-r1100',['D:\001-�߽���\01-���й���\��ʿС����ˮ������\���\����\����ͼ']);



