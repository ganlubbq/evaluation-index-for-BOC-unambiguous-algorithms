
clear;
clc;
%%
%正弦BOC参数
c=CA_code(1);%得到CA码序列1
L_CA=length(c);%CA码序列长度
m=10;n=5;
Rc=n*1.023e6;%码速率
Tc=1/Rc;%码片长度
f_sample=100e6;%采样频率
T_sample=1/f_sample;
Tp=1e-3-T_sample;%相干积分时间1ms
fs=m*1.023e6;
Ts=1/fs/2;
%%
%%%相关器间隔
BW=30*1.023e6;d=0.1*Tc;VT_N=12;Dz=1.42e-4;%BOC(10,5)相关器间隔
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
N_BW=10000;
f=linspace(-BW/2,BW/2,N_BW);
PSD_BOC=PSDcal_BOCs(f, fs, Tc);
power_loss_filter_dB=10*log10(trapz(f,PSD_BOC));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
C=1;%载波功率

N_C=1;
% C_N0_dB=linspace(20,45,N_C)-power_loss_filter_dB;
C_N0_dB=45;
C_N0=10.^(C_N0_dB/10);
N0=C./C_N0;%单边噪声功率谱密度
I_NoisePower=N0*BW*f_sample/BW;%在接收带宽内的噪声功率,因为在滤波后，噪声功率减为此处的BW/fsample，为了使滤波后噪声功率保持2N0*BW(射频变基带噪声谱密度变2倍)，在此处乘以fsample/BW
Q_NoisePower=N0*f_sample;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t0=0.0*Ts;%真实传播时间，初始误差在一个码片内
% t0=-0.9648*Tc;%真introduce false lock
t_begin=t0;
t_end=t_begin+Tp;
t_ref_begin_scan=0;
% n_loop=100000;
n_loop=10000;

Trackerror=zeros(1,n_loop);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%
error_x=zeros(1,n_loop);
error_y=zeros(1,n_loop);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[S_CA_receiver,t]=yt_BOCs_function(c,t_begin,t_end,Tc,fs,f_sample);
N_zong=length(t);

TrackErrRMS=zeros(1,N_C);
h_wait=waitbar(0);

Num_false_acquisition=200;
t_ref_begin_scan=linspace(-1*Tc,Tc,Num_false_acquisition);

for m=1:Num_false_acquisition
    for k=1:N_C
        tic;
        t0=0.0*Ts;%真实传播时间，初始误差在一个码片内

        t_begin=t0;
        t_end=t_begin+Tp;
        t_ref_begin=t_ref_begin_scan(m);
        
        
        Counter_VE=0;%VE计数器
        Counter_VL=0;%VL计数器
        
        for n=1:n_loop

            t_ref_end=t_ref_begin+Tp;
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %%
        [s_ref_P,t_P]=yt_BOCs_function(c,t_ref_begin,t_ref_end,Tc,fs,f_sample);

        [s_ref_E,t_E]=yt_BOCs_function(c,t_ref_begin+d/2,t_ref_end+d/2,Tc,fs,f_sample);
        [s_ref_L,t_L]=yt_BOCs_function(c,t_ref_begin-d/2,t_ref_end-d/2,Tc,fs,f_sample);
        [s_ref_VE,t_VE]=yt_BOCs_function(c,t_ref_begin+Ts,t_ref_end+Ts,Tc,fs,f_sample);%VE
        [s_ref_VL,t_VL]=yt_BOCs_function(c,t_ref_begin-Ts,t_ref_end-Ts,Tc,fs,f_sample);%VL  
     
         %%%%%%%%%%%%%%%%%%%%%%%%%%   
         %%
        S_receiver_I=sqrt(2*C)*S_CA_receiver+sqrt(I_NoisePower(k))*randn(1,N_zong);
        S_receiver_Q=sqrt(Q_NoisePower(k))*randn(1,N_zong);

        fft_sig  = fft(S_receiver_I + 1i*S_receiver_Q);
        L_res   = round(BW/f_sample/2*N_zong);
        fft_sig(L_res+1:end-L_res)  = 0;
        sigBandL = ifft(fft_sig);
        RecSigI = real(sigBandL);
        RecSigQ = imag(sigBandL);

       %%
        Int_Ie = sum(s_ref_E .* RecSigI)/N_zong;Int_Ip = sum(s_ref_P .* RecSigI)/N_zong;Int_Il = sum(s_ref_L.* RecSigI)/N_zong;
        Int_Qe = sum(s_ref_E.* RecSigQ)/N_zong;Int_Qp = sum(s_ref_P.* RecSigQ)/N_zong;Int_Ql = sum(s_ref_L.* RecSigQ)/N_zong;
        
        Int_Ive = sum(s_ref_VE .* RecSigI)/N_zong;Int_Ivl = sum(s_ref_VL .* RecSigI)/N_zong;
        Int_Qve = sum(s_ref_VE.* RecSigQ)/N_zong;Int_Qvl = sum(s_ref_VL.* RecSigQ)/N_zong;
 
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  
        %% bump-jumping计数器
        if abs(Int_Ive)>abs(Int_Ip)&&abs(Int_Ive)>abs(Int_Ivl)
            Counter_VE=Counter_VE+1;
            if Counter_VL>0
                Counter_VL=Counter_VL-1;
            end
        end
        if abs(Int_Ivl)>abs(Int_Ip)&&abs(Int_Ivl)>abs(Int_Ive)
            Counter_VL=Counter_VL+1;
            if Counter_VE>0
                Counter_VE=Counter_VE-1;
            end
        end
         if abs(Int_Ivl)<abs(Int_Ip)&&abs(Int_Ive)<abs(Int_Ip)
            if Counter_VL>0
                Counter_VL=Counter_VL-1;
            end
            if Counter_VE>0
                Counter_VE=Counter_VE-1;
            end
        end
        %% 鉴别器     
        DiscrimOut  = (Int_Ie^2+Int_Qe^2)-(Int_Il^2+Int_Ql^2);%鉴别器2

        %%
            error_x(n)=(t_begin-t_ref_begin)/Tc;%真实误差
            error_y(n)=DiscrimOut;%鉴别器输出


            Filter_output=DiscrimOut*Dz;%一阶环路滤波器

            t_ref_begin=t_ref_begin+Filter_output*Tc;
                
            if Counter_VE>=VT_N
                t_ref_begin=t_ref_begin+Ts;
                Counter_VE=0;Counter_VL=0;
            end
            if Counter_VL>=VT_N
                t_ref_begin=t_ref_begin-Ts;
                Counter_VE=0;Counter_VL=0;
            end
            
            
            Trackerror(n)=(t_ref_begin-t_begin)*3e8;%跟踪误差

            temp_string=['已运行' num2str(floor(((k-1)*n_loop+n+m)/(N_C*n_loop*Num_false_acquisition)*10000)/100) '%'];
            waitbar(((k-1)*n_loop+n+m)/(N_C*n_loop*Num_false_acquisition),h_wait,temp_string);
        end
    end
    TrackErrSTD(m)=std(error_x);
    error_recorder(m,:)=error_x;
   
    toc;
end
savefile='false_lock_index_BJ_BOC_10_5_30M_01Tc_45dBHz.mat';
save(savefile);


close(h_wait);
%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% plot false lock index
figure;plot(t_ref_begin_scan/Tc,TrackErrSTD,'Linewidth',2);grid on;
xlabel('false acuiqisition results (chips)');
ylabel('code tracking error std (chips)');
saveas(gcf,'false_lock_index_BJ_BOC_10_5_30M_01Tc_45dBHz');
