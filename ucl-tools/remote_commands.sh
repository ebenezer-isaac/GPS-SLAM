# Copy TSDF engine to local /tmp for faster loading, then start viewer
killall remote_viewer 2>/dev/null || true
sleep 1

echo "=== Copying TSDF engine to local disk ==="
if [ ! -d /tmp/tsdf_engine_cache ]; then
    cp -r output/release/replica/office0/tsdf_engine /tmp/tsdf_engine_cache
    echo "Copied 1.1GB TSDF to /tmp"
else
    echo "TSDF already cached in /tmp"
fi
ls -lh /tmp/tsdf_engine_cache/ | head -5

# Also copy model
if [ ! -f /tmp/gs_model_cache/model.pt ]; then
    mkdir -p /tmp/gs_model_cache
    cp -r output/release/replica/office0/gs_model/* /tmp/gs_model_cache/
    echo "Copied model to /tmp"
fi

# Create fast config pointing to /tmp
cat > /tmp/viewer_fast.yaml << 'YAMLEOF'
workspace_dir: /tmp/gps_slam_viewer
dev_id: 0
work_mode: eval
port: 6688

READER:
  input_dir: data/replica/office0
  image_path: camera
  pose_path: camera
  depth_path: depth
  pcd_name: "sampled_pcd_50w"
  depth_scale: 6553.5
  scene_scale: 1.0
  start_frame: 0
  end_frame: 1
  frame_step: 1
  intrinsics: [600, 600, 599.5, 339.5]
  image_shape: [1200, 680]
  downscale_factor: 1
  test_split_interval: -1

PIPE:
  train_mode: ges
  max_iterations: 10000
  enable_densify: false
  eval_after_train: false
  save_after_train: false
  selected_cam_idx: -1
  model_path: "/gs_model"
  log_path: "/log"
  eval_path: "/vis"
  log_iter: 1000
  weight_configs:
    ssim_weight: 0.0
    depth_weight: 0.0
  vis_configs:
    color_error_max: 0.1
    depth_error_max: 0.1
    depth_vis_max: 5
    depth_vis_min: 0
    alpha_vis_max: 5
  log_slam_state: false
  new_gs_sample_ratio: 0.25
  color_error_thres: 0.05
  localframe_cam_window_length: 2
  localframe_cam_window_interval: 5
  local_opt_iters: 20
  local_opt_interval: 10
  keyframe_theta_thres: 30
  keyframe_trans_thres: 0.3
  keyframe_select_max: 7
  keyframe_sample_configs:
    weight_intervel: 0.01
    loss_thres: 0.02
    opt_thres: 50
    sample_method: random
  remove_configs:
    large_scale_thres: 0.1
    small_scale_thres: 0.003
    low_opac_thres: 0.005
  TSDF:
    voxel_size: 0.005
    trunc_dist: 0.02
    viewFrustum_min: 0.2
    viewFrustum_max: 10
    load_images: false
    use_gt_pose: true
    saved_mesh: ""
    saved_engine: "tsdf_engine/"
    saved_images: ""

MODEL:
  render_method: ges
  max_gs_radii: 100
  delta_depth: 0.1
  sh_degree: 3
  sh_degree_interval: 0
  max_init_scale: 0.01
  min_init_scale: -1
  default_opacities: 0.5
  means_lr: 0.00016
  means_lr_final: 0.0000016
  scales_lr: 0.005
  quats_lr: 0.001
  featuresDc_lr: 0.0025
  featuresRest_lr: 0.0005
  opacities_lr: 5e-2
  exposure_lr: 0.003
  use_exposure: false
  densify_start_iter: 500
  densify_end_iter: 6000
  densify_interval: 100
  densify_grad_thres: 0.0002
  densify_large_thres: 0.01
  split_screen_size: 0.05
  reset_opacity_interval: 3000
  prune_opacity_thres: 0.005
YAMLEOF

# Create workspace with symlinks to cached data
mkdir -p /tmp/gps_slam_viewer
ln -sf /tmp/gs_model_cache /tmp/gps_slam_viewer/gs_model
ln -sf /tmp/tsdf_engine_cache /tmp/gps_slam_viewer/tsdf_engine

echo ""
echo "=== Starting viewer from local disk ==="
nohup ./build/remote_viewer /tmp/viewer_fast.yaml > viewer_server.log 2>&1 &
echo "PID: $!"

sleep 30
echo ""
tail -5 viewer_server.log 2>/dev/null | tr '\r' '\n' | tail -5
echo ""
ss -tlnp 2>/dev/null | grep 6688 && echo "READY ON PORT 6688!" || echo "Still loading..."
