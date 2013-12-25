function checking_stats(X, y, mean_family, mean_params, ...
           complete_covfunc, complete_hypers, decomp_list, ...
           decomp_hypers, lik_family_, lik_params, figname, ...
           idx, make_plots)
% Computes model checking statustucs and makes plots
                 
%%%%%%%%%%%
% WARNING %
%%%%%%%%%%%
% - Ignores mean
% - Ignores lik - assumes provides a noise parameter

if isempty(lik_params)
    log_noise = -inf;
else
    log_noise = lik_params(0);
end
noise_var = exp(2*log_noise);

% Convert to double in case python saved as integers
X = double(X);
y = double(y);

%%%% TODO - function should accept a mean function
%y = y - mean(y);

%%%% TODO - turn into parameters
left_extend = 0.1;  % What proportion to extend beyond the data range.
right_extend = 0.4;

%%%% TODO - parameter
num_interpolation_points = 2000;

x_left = min(X) - (max(X) - min(X))*left_extend;
x_right = max(X) + (max(X) - min(X))*right_extend;
xrange = linspace(x_left, x_right, num_interpolation_points)';
xrange_no_extrap = linspace(min(X), max(X), num_interpolation_points)';

complete_sigma = feval(complete_covfunc{:}, complete_hypers, X) + eye(length(y)).*noise_var;

% Plot each component without data
qq_d_max_p = zeros(numel(decomp_list),1);
qq_d_min_p = zeros(numel(decomp_list),1);
acf_min_p = zeros(numel(decomp_list),1);
acf_min_loc_p = zeros(numel(decomp_list),1);
pxx_max_p = zeros(numel(decomp_list),1);
pxx_max_loc_p = zeros(numel(decomp_list),1);

for j = 1:numel(decomp_list)
    i = idx(j);
    cur_cov = decomp_list{i};
    cur_hyp = decomp_hypers{i};
    
    % Compute mean and variance for this kernel.
    decomp_sigma = feval(cur_cov{:}, cur_hyp, X);
    
    data_mean = decomp_sigma' / complete_sigma * y;
    data_covar = decomp_sigma - decomp_sigma' / complete_sigma * decomp_sigma;
    
    % Plot sample qq
    
    samples = 1000;
    
    many_prior_samples = chol(non_singular(decomp_sigma))' * ...
                    randn(length(y), 100);% ./ ...
                    %repmat(sqrt(diag(decomp_sigma)), 1, samples);
    q_values = linspace(0,1,length(y)+2)';
    q_values = q_values(2:(end-1));
    prior_quantiles = quantile(many_prior_samples(:), q_values);
    prior_samples = chol(non_singular(decomp_sigma))' * ...
                    randn(length(y), samples);% ./ ...
                    %repmat(sqrt(diag(decomp_sigma)), 1, samples);
    prior_qq = zeros(length(y), samples);
    %repeated_samples = repmat(many_prior_samples(:)', length(y), 1);
    %repeated_samples = repeated_samples + ... % To break ties
    %                   0.001*max(max(many_prior_samples))*randn(size(repeated_samples));
    prior_qq_d_max = zeros(samples, 1);
    prior_qq_d_min = zeros(samples, 1);
    for iter = 1:samples
        %a = normcdf(sort(prior_samples(:,iter)));
        a = sort(prior_samples(:,iter));
        %a = sum(repmat(sort(prior_samples(:,iter)), 1, length(repeated_samples)) > repeated_samples, 2) ./ length(repeated_samples);
        prior_qq(:,iter) = a;
        differences = a - prior_quantiles;
        prior_qq_d_max(iter) = differences(differences == max(differences));
        prior_qq_d_min(iter) = differences(differences == min(differences));
    end

    post_samples = (repmat(data_mean, 1, samples) + chol(non_singular(data_covar))' * ...
                    randn(length(y), samples));% ./ ...
                   %repmat(sqrt(diag(data_covar)), 1, samples);
    post_qq = zeros(length(y), samples);
    post_qq_d_max = zeros(samples, 1);
    post_qq_d_min = zeros(samples, 1);
    for iter = 1:samples
        %a = normcdf(sort(post_samples(:,iter)));
        a = sort(post_samples(:,iter));
        %a = sum(repmat(sort(post_samples(:,iter)), 1, length(repeated_samples)) > repeated_samples, 2) ./ length(repeated_samples);
        post_qq(:,iter) = a;
        differences = a - prior_quantiles;
        post_qq_d_max(iter) = differences(differences == max(differences));
        post_qq_d_min(iter) = differences(differences == min(differences));
    end
    
    % Is the value of the distance extreme?
    qq_d_max_p(j) = sum(prior_qq_d_max > post_qq_d_max + 0.0001*max(post_qq_d_max)*randn(size(post_qq_d_max))) / length(post_qq_d_max);
    qq_d_min_p(j) = sum(prior_qq_d_min < post_qq_d_min + 0.0001*max(post_qq_d_min)*randn(size(post_qq_d_min))) / length(post_qq_d_min);
    
    if make_plots
        figure(i + 1); clf; hold on;
        two_band_plot(prior_quantiles, ...%linspace(0, 1, length(y))', ...
                      mean(prior_qq, 2), ...
                      quantile(prior_qq, 0.95, 2), ...
                      quantile(prior_qq, 0.05, 2), ...
                      mean(post_qq, 2), ...
                      quantile(post_qq, 0.95, 2), ...
                      quantile(post_qq, 0.05, 2));
        title(sprintf('QQ uncertainty plot for component %d', j));
        filename = sprintf('%s_qq_bands_%d.fig', figname, j);
        saveas( gcf, filename );  
    end
    %hold off;
    
    % Compute kernel at grid to compute acf and periodogram
    %%%% TODO - this can make things a little weird when periods line up
    %%%%      - with data
    
    x_grid = linspace(min(X), max(X), numel(X))';
    grid_distance = x_grid(2) - x_grid(1);
    
    complete_sigma_grid = feval(complete_covfunc{:}, complete_hypers, x_grid);
    decomp_sigma_grid = feval(cur_cov{:}, cur_hyp, x_grid);
    
    data_mean_grid = decomp_sigma_grid' / complete_sigma_grid * y;
    data_covar_grid = decomp_sigma_grid - decomp_sigma_grid' / complete_sigma_grid * decomp_sigma_grid;
    
    % Plot sample acf
    
    samples = 1000;
    
    prior_samples = chol(non_singular(decomp_sigma_grid))' * randn(length(y), samples);
    prior_acf = autocorr(prior_samples(:,1), length(y) -1);
    prior_acf = zeros(length(prior_acf), samples);
    prior_acf_min_loc = zeros(samples,1);
    prior_acf_min = zeros(samples,1);
    for iter = 1:samples
        prior_acf(:,iter) = autocorr(prior_samples(:,iter), length(y) -1);
        prior_acf_min_loc(iter) = find(prior_acf(:,iter) == min(prior_acf(:,iter)));
        prior_acf_min(iter) = min(prior_acf(:,iter));
    end

    post_samples = (repmat(data_mean_grid, 1, samples) + chol(non_singular(data_covar_grid))' * ...
                    randn(length(y), samples));
    post_acf = autocorr(post_samples(:,1), length(y) -1);
    post_acf = zeros(length(post_acf), samples);
    post_acf_min_loc = zeros(samples,1);
    post_acf_min = zeros(samples,1);
    for iter = 1:samples
        post_acf(:,iter) = autocorr(post_samples(:,iter), length(y) -1);
        post_acf_min_loc(iter) = find(post_acf(:,iter) == min(post_acf(:,iter)));
        post_acf_min(iter) = min(post_acf(:,iter));
    end
    
    % Are the values extreme?
    acf_min_p(j) = sum(prior_acf_min < post_acf_min + 0.0001*max(post_acf_min)*randn(size(post_acf_min))) / length(post_acf_min);
    acf_min_loc_p(j) = sum(prior_acf_min_loc < post_acf_min_loc + 0.0001*max(post_acf_min_loc)*randn(size(post_acf_min_loc))) / length(post_acf_min_loc);

    if make_plots
        figure(i + 1); clf; hold on;
        two_band_plot((1:size(post_acf, 1))' * grid_distance, ...
                      mean(prior_acf, 2), ...
                      quantile(prior_acf, 0.95, 2), ...
                      quantile(prior_acf, 0.05, 2), ...
                      mean(post_acf, 2), ...
                      quantile(post_acf, 0.95, 2), ...
                      quantile(post_acf, 0.05, 2));
        title(sprintf('ACF uncertainty plot for component %d', j));
        ylabel('Correlation coefficient');
        xlabel('Lag');
        filename = sprintf('%s_acf_bands_%d.fig', figname, j);
        saveas( gcf, filename );
    end
    
    % Plot sample periodogram
    
    samples = 1000;
    
    prior_samples = chol(non_singular(decomp_sigma_grid))' * randn(length(y), samples);
    prior_pxx = 10 * log10(periodogram(prior_samples(:,1)));
    prior_pxx = zeros(length(prior_pxx), samples);
    prior_pxx_max_loc = zeros(samples,1);
    prior_pxx_max = zeros(samples,1);
    for iter = 1:samples
        prior_pxx(:,iter) = 10 * log10(periodogram(prior_samples(:,iter)));
        prior_pxx_max_loc(iter) = find(prior_pxx(:,iter) == max(prior_pxx(:,iter)));
        prior_pxx_max(iter) = max(prior_pxx(:,iter));
    end

    post_samples = (repmat(data_mean_grid, 1, samples) + chol(non_singular(data_covar_grid))' * ...
                    randn(length(y), samples));
    post_pxx = 10 * log10(periodogram(post_samples(:,1)));
    post_pxx = zeros(length(post_pxx), samples);
    post_pxx_max_loc = zeros(samples,1);
    post_pxx_max = zeros(samples,1);
    for iter = 1:samples
        post_pxx(:,iter) = 10 * log10(periodogram(post_samples(:,iter)));
        post_pxx_max_loc(iter) = find(post_pxx(:,iter) == max(post_pxx(:,iter)));
        post_pxx_max(iter) = max(post_pxx(:,iter));
    end
    
    % Are the values extreme?
    pxx_max_p(j) = sum(prior_pxx_max < post_pxx_max + 0.0001*max(post_pxx_max)*randn(size(post_pxx_max))) / length(post_pxx_max);
    pxx_max_loc_p(j) = sum(prior_pxx_max_loc < post_pxx_max_loc + 0.0001*max(post_pxx_max_loc)*randn(size(post_pxx_max_loc))) / length(post_pxx_max_loc);

    if make_plots
        figure(i + 1); clf; hold on;
        two_band_plot(linspace(0,1,size(prior_pxx,1))', ...
                      mean(prior_pxx, 2), ...
                      quantile(prior_pxx, 0.95, 2), ...
                      quantile(prior_pxx, 0.05, 2), ...
                      mean(post_pxx, 2), ...
                      quantile(post_pxx, 0.95, 2), ...
                      quantile(post_pxx, 0.05, 2));
        title(sprintf('Periodogram uncertainty plot for component %d', j));
        ylabel('Power / frequency');
        xlabel('Normalised frequency');
        filename = sprintf('%s_pxx_bands_%d.fig', figname, j);
        saveas( gcf, filename );    
    end
end

if make_plots
    % Plot LOO posterior predictive, residuals and QQ

    p_point_LOO = nan(size(X));
    mean_LOO = nan(size(X));
    var_LOO = nan(size(X));

    K = complete_sigma;

    for i = 1:length(X)
        not_i = [1:(i-1),(i+1):length(X)];

        K_ii = K(not_i,not_i);
        K_i = K(i,not_i);
        y_i = y(not_i);

        mean_LOO(i) = K_i * (K_ii \ y_i);
        var_LOO(i) = K(i,i) - K_i * (K_ii \ K_i');
        standard = (y(i) - mean_LOO(i)) ./ sqrt(var_LOO(i));

        p_point_LOO(i) = normcdf(standard);
    end

    figure(333); clf; hold on;
    mean_var_plot( X, y, ...
                   X, ...
                   mean_LOO, 2.*sqrt(var_LOO));

    title(sprintf('LOO posterior predictive'));
    filename = sprintf('%s_loo_pp.fig', figname);
    saveas( gcf, filename );

    figure(444); clf; hold on;
    mean_var_plot( X, p_point_LOO, ...
                   X, ...
                   mean_LOO, 2.*sqrt(var_LOO), ...
                   false, true);

    title(sprintf('LOO residuals'));
    filename = sprintf('%s_loo_resid.fig', figname);
    saveas( gcf, filename );

    figure(555); clf; hold on;
    qq_uniform_plot(p_point_LOO);

    title(sprintf('LOO residuals QQ-plot'));
    filename = sprintf('%s_loo_qq.fig', figname);
    saveas( gcf, filename );

    % Plot LCO posterior predictives, residuals and QQ

    chunk_size = 0.1;

    p_point_LOO = nan(size(X));
    mean_LOO = nan(size(X));
    var_LOO = nan(size(X));

    K = complete_sigma;

    for i = 1:length(X)
        not_close = abs(X-X(i)) > ((max(X) - min(X)) * chunk_size * 0.5);

        K_ii = K(not_close,not_close);
        K_i = K(i,not_close);
        y_i = y(not_close);

        mean_LOO(i) = K_i * (K_ii \ y_i);
        var_LOO(i) = K(i,i) - K_i * (K_ii \ K_i');
        standard = (y(i) - mean_LOO(i)) ./ sqrt(var_LOO(i));

        p_point_LOO(i) = normcdf(standard);
    end

    figure(777); clf; hold on;
    mean_var_plot( X, y, ...
                   X, ...
                   mean_LOO, 2.*sqrt(var_LOO));

    title(sprintf('LCO posterior predictive'));
    filename = sprintf('%s_lco_pp.fig', figname);
    saveas( gcf, filename );

    figure(888); clf; hold on;
    mean_var_plot( X, p_point_LOO, ...
                   X, ...
                   mean_LOO, 2.*sqrt(var_LOO), ...
                   false, true);

    title(sprintf('LCO residuals'));
    filename = sprintf('%s_lco_resid.fig', figname);
    saveas( gcf, filename );

    figure(999); clf; hold on;
    qq_uniform_plot(p_point_LOO);

    title(sprintf('LCO residuals QQ-plot'));
    filename = sprintf('%s_lco_qq.fig', figname);
    saveas( gcf, filename );

    % Plot z score residuals

    L = chol(K);
    z = (L') \ y;
    p = normcdf(z);

    figure(123); clf; hold on;
    mean_var_plot( X, p, ...
                   X, ...
                   mean_LOO, 2.*sqrt(var_LOO), ...
                   false, true);

    title(sprintf('z score residuals'));
    filename = sprintf('%s_z_resid.fig', figname);
    saveas( gcf, filename );

    figure(234); clf; hold on;
    qq_uniform_plot(p);

    title(sprintf('z score residuals QQ-plot'));
    filename = sprintf('%s_z_qq.fig', figname);
    saveas( gcf, filename );
end

% Save data to file

save(sprintf('%s_checking_stats.mat', figname), ...
     'qq_d_min_p', 'qq_d_max_p', ...
     'acf_min_p', 'acf_min_loc_p', ...
     'pxx_max_p', 'pxx_max_loc_p');
 
% Convert everything to pdf

% dirname = fileparts(figname);
% files = dir([dirname, '/*.fig']);
% for f_ix = 1:numel(files)
%     curfile = [dirname, '/', files(f_ix).name];
%     h = open(curfile);
%     outfile = [dirname, '/', files(f_ix).name];
%     pdfname = strrep(outfile, '.fig', '')
%     save2pdf( pdfname, gcf, 600, true );
%     %export_fig(pdfname, '-pdf');
%     close all
% end

end


function mean_var_plot( xdata, ydata, xrange, forecast_mu, forecast_scale, small_plot, data_only, no_data )

    if nargin < 6; small_plot = false; end
    if nargin < 7; data_only = false; end
    if nargin < 8; no_data = false; end

    % Figure settings.
    lw = 1.2;
    opacity = 1;
    light_blue = [227 237 255]./255;
    
    if ~data_only
        % Plot confidence bears.
        jbfill( xrange', ...
            forecast_mu' + forecast_scale', ...
            forecast_mu' - forecast_scale', ...
            light_blue, 'none', 1, opacity); hold on;   
    end
    
    
    set(gca,'Layer','top');  % Stop axes from being overridden.
        
    % Plot data.
    %plot( xdata, ydata, 'ko', 'MarkerSize', 2.1, 'MarkerFaceColor', facecol, 'MarkerEdgeColor', facecol ); hold on;    
    %h_dots = line( xdata, ydata, 'Marker', '.', 'MarkerSize', 2, 'MarkerEdgeColor',  [0 0 0], 'MarkerFaceColor', [0 0 0], 'Linestyle', 'none' ); hold on;    
    if ~no_data
        plot( xdata, ydata, 'k.');
    end
 
    if ~data_only
        % Plot mean function.
        plot(xrange, forecast_mu, 'Color', colorbrew(2), 'LineWidth', lw); hold on;
    end
        

    
    %set(gca, 'Children', [h_dots, h_bars, h_mean ] );
    %e1 = (max(xrange) - min(xrange))/300;
    %for i = 1:length(xdata)
    %   line( [xdata(i) - e1, xdata(i) + e1], [ydata(i) + e1, ydata(i) + e1], 'Color', [0 0 0 ], 'LineWidth', 2 );
    %end
    %set_fig_units_cm( 12,6 );   
    %ag_plot_little_circles_no_alpha(xdata, ydata, 0.02, [0 0 0])
    
    % Make plot prettier.
    set(gcf, 'color', 'white');
    set(gca, 'TickDir', 'out');
    
    xlim([min(xrange), max(xrange)]);
    if small_plot
        totalrange = (max(xrange) - min(xrange));
        xlim([min(xrange) + totalrange*0.7, max(xrange) - totalrange*0.05]);
    end    
    
    % Plot a vertical bar to indicate the start of extrapolation.
    if ~all(forecast_mu == 0) && ~(max(xdata) == max(xrange))  % Don't put extrapolation line on residuals plot.
        y_lim = get(gca,'ylim');
        line( [max(xdata), max(xdata)], y_lim, 'Linestyle', '--', 'Color', [0.3 0.3 0.3 ]);
    end 
    
    % Plot a vertical bar to indicate the start of extrapolation.
    if ~all(forecast_mu == 0) && ~(min(xdata) == min(xrange))  % Don't put extrapolation line on residuals plot.
        y_lim = get(gca,'ylim');
        line( [min(xdata), min(xdata)], y_lim, 'Linestyle', '--', 'Color', [0.3 0.3 0.3 ]);
    end 
    
    %set(get(gca,'XLabel'),'Rotation',0,'Interpreter','latex', 'Fontsize', fontsize);
    %set(get(gca,'YLabel'),'Rotation',90,'Interpreter','latex', 'Fontsize', fontsize);
    %set(gca, 'TickDir', 'out')
    
    set_fig_units_cm( 16,8 );
    
    if small_plot
        set_fig_units_cm( 6, 6 );
    end
end

function qq_uniform_plot( sample )
    
    lw = 1.2;

    sample = sort(sample);
    U = linspace(0,1,length(sample)+2);
    U = U(2:(end-1));
    
    plot(U, U, 'Color', colorbrew(2), 'LineWidth', lw);
    plot(U, sample, 'k.');
    
    xlim([0,1]);
    ylim([0,1]);
    
    % Make plot prettier.
    set(gcf, 'color', 'white');
    set(gca, 'TickDir', 'out');
    
    xlabel('Uniform quantiles');
    ylabel('Sample quantiles');
    
    set_fig_units_cm( 16,8 );
end