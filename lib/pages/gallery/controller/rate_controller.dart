import 'package:eros_fe/common/service/controller_tag_service.dart';
import 'package:eros_fe/models/base/eh_models.dart';
import 'package:eros_fe/network/api.dart';
import 'package:eros_fe/utils/logger.dart';
import 'package:eros_fe/utils/toast.dart';
import 'package:get/get.dart';

import 'gallery_page_controller.dart';
import 'gallery_page_state.dart';

class RateController extends GetxController {
  RateController();

  late double rate;

  late GalleryPageController pageController;
  GalleryPageState get _pageState => pageController.gState;
  GalleryProvider? get _item => _pageState.galleryProvider;

  @override
  void onInit() {
    super.onInit();
    pageController = Get.find(tag: pageCtrlTag);
    rate = _item?.rating ?? 0;
  }

  Future<void> rating() async {
    if (_item == null) {
      return;
    }

    logger.t('rating $rate');
    logger.t('${_item?.apiuid} ${_item?.apikey}');
    logger.t('${(rate * 2).round()}');
    final Map<String, dynamic> rultMap = await Api.setRating(
      apikey: _item!.apikey ?? '',
      apiuid: _item!.apiuid ?? '',
      gid: _item!.gid ?? '0',
      token: _item!.token ?? '',
      rating: (rate * 2).round(),
    );
    final ratingUsr = double.tryParse(rultMap['rating_usr']?.toString() ?? '');
    final ratingAvg = double.tryParse(rultMap['rating_avg']?.toString() ?? '');
    final ratingCnt = rultMap['rating_cnt'] as int?;
    final colorRating = rultMap['rating_cls'] as String?;
    if (ratingUsr == null || ratingAvg == null || ratingCnt == null || colorRating == null) {
      logger.e('rating response missing fields: $rultMap');
      showToast('Rating failed: unexpected response');
      return;
    }
    pageController.afterRating(
      ratingUsr: ratingUsr,
      ratingAvg: ratingAvg,
      ratingCnt: ratingCnt,
      colorRating: colorRating,
    );
    showToast('Ratting successfully');
  }
}
